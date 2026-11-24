#!/usr/bin/env python3
"""Build Claw'd's original 5×7 dialogue face with the Python standard library."""
import struct
from pathlib import Path

# Each pair of hex digits is a five-pixel row, top to bottom.
LETTERS = """
A 0e11111f111111
B 1e11111e11111e
C 0e11101010110e
D 1c12111111121c
E 1f10101e10101f
F 1f10101e101010
G 0e11101711110f
H 1111111f111111
I 0e04040404040e
J 0702020212120c
K 11121418141211
L 1010101010101f
M 111b1515111111
N 11191915131311
O 0e11111111110e
P 1e11111e101010
Q 0e11111115120d
R 1e11111e141211
S 0f10100e01011e
T 1f040404040404
U 1111111111110e
V 11111111110a04
W 1111111515150a
X 11110a040a1111
Y 11110a04040404
Z 1f01020408101f
a 00000e010f110f
b 1010161911111e
c 00000e1110110e
d 01010d1311110f
e 00000e111f100e
f 0609081c080808
g 00000f11110f010e
h 10101619111111
i 04000c0404040e
j 020006020202120c
k 10101214181412
l 0c04040404040e
m 00001a15151515
n 00001619111111
o 00000e1111110e
p 00001e11111e1010
q 00000f11110f0101
r 00001619101010
s 00000f100e011e
t 08081c08080906
u 0000111111130d
v 00001111110a04
w 0000111115150a
x 0000110a040a11
y 00001111110f010e
z 00001f0204081f
0 0e11131519110e
1 040c040404040e
2 0e11010204081f
3 1e01010e01011e
4 02060a121f0202
5 1f101e0101011e
6 0e10101e11110e
7 1f010204080808
8 0e11110e11110e
9 0e11110f01010e
! 04040404040004
? 0e110102040004
. 00000000000004
, 0000000000000408
: 00000400000400
; 00000400000408
- 0000000e000000
_ 0000000000001f
+ 0000041f040000
= 00001f001f0000
/ 01020204080810
% 19190204081313
@ 0e11171517100e
& 0c12140c15120d
# 0a0a1f0a1f0a0a
* 00150e1f0e1500
' 04040800000000
" 0a0a1400000000
( 02040808080402
) 08040202020408
[ 0e08080808080e
] 0e02020202020e
{ 06040408040406
} 0c04040204040c
< 01020408040201
> 10080402040810
| 04040404040404
$ 040f140e051e04
^ 040a1100000000
~ 00000009160000
ß 0c121214121216
· 00000004000000
… 00000000000015
"""
GLYPHS = {char: list(bytes.fromhex(bits)) for char, bits in
          (line.split() for line in LETTERS.strip().splitlines())}
GLYPHS.update({" ": [], "\u00a0": [], "\\": [16, 8, 8, 4, 2, 2, 1],
               "\u2019": [4, 4, 8], "\u2018": [2, 4, 4], "\u2013": [0, 0, 0, 31],
               "\u2014": [0, 0, 0, 31], "„": [0, 0, 0, 0, 0, 0, 10, 20],
               "“": [5, 10, 10], "”": [10, 10, 20]})
for letter, base in zip("ÄÖÜäöü", "AOUaou"):
    GLYPHS[letter] = ([10, 0] + GLYPHS[base]) if base.isupper() else ([10, 0] + GLYPHS[base][2:])


def pack(fmt, *args):
    return struct.pack(">" + fmt, *args)


def sums(data):
    return sum(n[0] for n in struct.iter_unpack(">I", data + bytes(-len(data) % 4))) & 0xFFFFFFFF


def outline(char, rows):
    top = 900 if char in "ÄÖÜ" else 700
    points, ends = [], []
    for i, value in enumerate(rows):
        start = None
        for col in range(6):
            lit = col < 5 and value & (16 >> col)
            if lit and start is None:
                start = col
            if not lit and start is not None:
                x, right, y = 100*start, 100*col, top - 100*(i+1)
                points.extend([(x, y), (x, y+100), (right, y+100), (right, y)])
                ends.append(len(points)-1)
                start = None
    if not points:
        return pack("hhhhh", 0, 0, 0, 0, 0)
    x, y = zip(*points)
    result = pack("hhhhh", len(ends), min(x), min(y), max(x), max(y))
    result += pack("H"*len(ends), *ends) + pack("H", 0) + bytes([1])*len(points)
    for axis in (x, y):
        result += pack("h"*len(axis), *(v-(axis[i-1] if i else 0) for i, v in enumerate(axis)))
    return result


def build():
    ordered = sorted(GLYPHS, key=ord)
    points = [outline("?", GLYPHS["?"])] + [outline(c, GLYPHS[c]) for c in ordered]
    offsets, outlines = [], bytearray()
    for glyph in points:
        offsets.append(len(outlines))
        outlines.extend(glyph + bytes(-len(glyph) % 4))
    offsets.append(len(outlines))
    n = len(points)
    table = {"glyf": bytes(outlines), "loca": pack("I"*len(offsets), *offsets),
             "head": pack("IIIIHHQQhhhhHHhhh", 0x10000,0x10000,0,0x5F0F3CF5,3,1000,0,0,0,-100,500,900,0,8,2,1,0),
             "hhea": pack("IhhhH",0x10000,900,-200,0,600) + pack("h"*11,0,100,500,1,0,0,0,0,0,0,0) + pack("H",n),
             "hmtx": pack("Hh",600,0)*n,
             "maxp": pack("I14H",0x10000,n,180,45,0,0,2,0,0,0,0,0,0,0,0),
             "post": pack("IIhhIIIII",0x30000,0,-100,50,1,0,0,0,0)}
    items = [(ord(c), i+1) for i, c in enumerate(ordered)] + [(65535, 0)]
    m = len(items)
    shift = m.bit_length()-1
    cmap = pack("7H",4,16+8*m,0,2*m,2*(1<<shift),shift,2*m-2*(1<<shift))
    codes = pack("H"*m, *(code for code, _ in items))
    cmap += codes + b"\0\0" + codes + pack("H"*m, *((idx-code)&65535 for code,idx in items)) + bytes(2*m)
    table["cmap"] = pack("HHHHI",0,1,3,1,12) + cmap
    table["OS/2"] = (pack("HhHHH",0,600,400,5,0) + pack("11h",650,600,0,75,650,600,0,300,60,260,0)
        + bytes([2,11,5,9,2,2,3,2,2,4]) + pack("IIII",3,0,0,0) + b"CLWD"
        + pack("HHHhhhHH",64,32,ord(ordered[-1]),900,-200,0,900,200))
    names = {1:"Clawd Dialogue",2:"Regular",3:"ClawdDialogue-Regular-1",4:"Clawd Dialogue Regular",
             5:"Version 1.0",6:"ClawdDialogue-Regular"}
    strings, records = bytearray(), bytearray()
    for key, val in names.items():
        data = val.encode("utf-16-be")
        records.extend(pack("6H",3,1,0x409,key,len(data),len(strings)))
        strings.extend(data)
    table["name"] = pack("3H",0,len(names),6+len(records)) + records + strings
    count = len(table)
    power = count.bit_length()-1
    header = pack("I4H",0x10000,count,16*(1<<power),power,16*(count-(1<<power)))
    directory, payload = bytearray(), bytearray()
    for name, data in sorted(table.items()):
        offset = len(header)+16*count+len(payload)
        directory.extend(name.encode()+pack("III",sums(data),offset,len(data)))
        if name == "head":
            head = offset
        payload.extend(data + bytes(-len(data)%4))
    font = bytearray(header + directory + payload)
    struct.pack_into(">I",font,head+8,(0xB1B0AFBA-sums(font))&0xFFFFFFFF)
    return font


if __name__ == "__main__":
    path = Path(__file__).resolve().parent.parent / "Resources/ClawdDialogue.ttf"
    path.write_bytes(build())
