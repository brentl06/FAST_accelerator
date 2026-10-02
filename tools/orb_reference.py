"""Independent integer reference and vectors for the FPGA ORB variant.

Run: python tools/orb_reference.py generate <directory>
     python tools/orb_reference.py check <directory>
Only sampling constants are shared with RTL; image, moment, convolution,
FAST/NMS and selection calculations below run independently in Python.
"""
import json
import math
import random
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PATTERN = ROOT / 'camera_accelerator.srcs/sources_1/new/orb_pattern.v'


def constants():
    pairs = re.findall(r"9'd\d+: begin x = (-?5'sd\d+); y = (-?5'sd\d+)", PATTERN.read_text())
    def value(s):
        return (-1 if s.startswith('-') else 1) * int(s.split('sd')[1])
    result = [(value(x), value(y)) for x, y in pairs]
    assert len(result) == 512
    return result


TRIG = [(math.floor(1024*math.cos(i*math.pi/16)+.5),
         math.floor(1024*math.sin(i*math.pi/16)+.5)) for i in range(32)]


def describe(image, x, y):
    mx = my = 0
    for dy in range(-15, 16):
        for dx in range(-15, 16):
            if dx*dx + dy*dy <= 225:
                p = image[y+dy][x+dx]
                mx += dx*p
                my += dy*p
    angle = max(range(32), key=lambda i: mx*TRIG[i][0]+my*TRIG[i][1])
    c, s = TRIG[angle]
    samples = []
    for px, py in constants():
        sx = x + (px*c-py*s+512)//1024
        sy = y + (px*s+py*c+512)//1024
        samples.append(sum(image[sy+j-1][sx+i-1]*a*b
                           for j,b in enumerate((1,2,1))
                           for i,a in enumerate((1,2,1))))
    bits = sum(int(samples[2*i] < samples[2*i+1]) << i for i in range(256))
    return angle, f'{bits:064x}'


RING = [(0,-3),(1,-3),(2,-2),(3,-1),(3,0),(3,1),(2,2),(1,3),
        (0,3),(-1,3),(-2,2),(-3,1),(-3,0),(-3,-1),(-2,-2),(-1,-3)]


def selected_features(image, threshold=20):
    h, w = len(image), len(image[0])
    scores = [[0]*w for _ in range(h)]
    for y in range(3,h-3):
        for x in range(3,w-3):
            d = [image[y+dy][x+dx]-image[y][x] for dx,dy in RING]
            best = max(min(sign*d[(i+k)%16] for k in range(9))
                       for i in range(16) for sign in (-1,1))
            scores[y][x] = best if best > threshold else 0
    cells = [[] for _ in range(4)]
    for y in range(20,h-20):
        for x in range(20,w-20):
            score = scores[y][x]
            if not score or any(scores[y+dy][x+dx] >= score for dy in (-1,0,1)
                                for dx in (-1,0,1) if dx or dy):
                continue
            cell = cells[(y//32)*2+x//32]
            item = (x,y,score)
            if len(cell) < 2:
                cell.append(item)
            else:
                lowest = min(range(2), key=lambda i: (cell[i][2],-i))
                if score > cell[lowest][2]:
                    cell[lowest] = item
    return [item for cell in cells for item in cell]


def generate(work):
    work.mkdir(parents=True,exist_ok=True)
    rng = random.Random(9721)
    patches = [[[7]*41 for _ in range(41)]]
    for c,s in TRIG:
        patches.append([[max(0,min(15,8+((x-20)*c+(y-20)*s)//2048))
                         for x in range(41)] for y in range(41)])
    patches += [[[rng.randrange(16) for _ in range(41)] for _ in range(41)] for _ in range(7)]
    with (work/'patches.hex').open('w') as f:
        for patch in patches:
            for row in patch:
                f.write(' '.join(f'{p:x}' for p in row)+'\n')
    expected = [describe(p,20,20) for p in patches]
    (work/'descriptor_expected.hex').write_text('\n'.join(f'{a:02x}{d}' for a,d in expected)+'\n')
    images = [[[rng.randrange(256) for _ in range(64)] for _ in range(64)],
              [[rng.randrange(256) for _ in range(64)] for _ in range(64)],
              [[128]*64 for _ in range(64)]]
    with (work/'frames.hex').open('w') as f:
        for image in images:
            for row in image:
                f.write(' '.join(f'{p:02x}' for p in row)+'\n')
    all_expected = []
    for frame_id, image in zip((0,2,3), images):
        gray = [[p>>4 for p in row] for row in image]
        for x,y,score in selected_features(image):
            angle,bits = describe(gray,x,y)
            all_expected.append([frame_id,x,y,score,angle,bits])
    assert all_expected and any(p[0]==2 for p in all_expected)
    (work/'accelerator_expected.json').write_text(json.dumps(all_expected,indent=2)+'\n')
    print(f'Generated {len(patches)} patches (all 32 orientations), 3 frames, {len(all_expected)} expected features')


def check(work):
    expected = json.loads((work/'accelerator_expected.json').read_text())
    got = []
    for line in (work/'accelerator_actual.txt').read_text().splitlines():
        fields = line.split()
        got.append([*map(int,fields[:5]),fields[5].lower()])
    assert got == expected, f'Frame/feature/score/orientation/descriptor mismatch:\nexpected={expected}\ngot={got}'
    print(f'PASS: {len(got)} end-to-end features match independent FAST, selection, orientation and all 256 descriptor bits')


if __name__ == '__main__':
    action, directory = sys.argv[1:]
    {'generate':generate,'check':check}[action](Path(directory))
