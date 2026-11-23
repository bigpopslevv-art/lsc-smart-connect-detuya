# Makes a silent copy of an MP3: keeps every frame header (same length/format), zeroes
# side info + audio data (part2_3_length=0, global_gain=0 -> decodes to silence). Drops ID3 tags.
import sys
BR = {  # Layer III bitrates (kbps): MPEG1, MPEG2/2.5
    1: [0,32,40,48,56,64,80,96,112,128,160,192,224,256,320],
    2: [0,8,16,24,32,40,48,56,64,80,96,112,128,144,160]}
SR = {3: [44100,48000,32000], 2: [22050,24000,16000], 0: [11025,12000,8000]}

def silence(d):
    i = 0
    if d[:3] == b'ID3':  # skip ID3v2 tag (syncsafe size)
        i = 10 + ((d[6] << 21) | (d[7] << 14) | (d[8] << 7) | d[9])
    out = bytearray(); frames = 0
    while i + 4 <= len(d):
        h = d[i:i+4]
        if h[0] != 0xFF or (h[1] & 0xE0) != 0xE0: break
        ver = (h[1] >> 3) & 3; layer = (h[1] >> 1) & 3
        assert layer == 1, 'not layer III'
        assert h[1] & 1, 'CRC frames not supported'
        br = BR[1 if ver == 3 else 2][h[2] >> 4] * 1000
        sr = SR[ver][(h[2] >> 2) & 3]; pad = (h[2] >> 1) & 1
        n = (144 if ver == 3 else 72) * br // sr + pad
        assert br and i + n <= len(d), 'bad frame'
        out += h + bytes(n - 4); i += n; frames += 1
    assert frames > 0
    return bytes(out), frames

if __name__ == '__main__':
    src, dst = sys.argv[1], sys.argv[2]
    data, frames = silence(open(src, 'rb').read())
    open(dst, 'wb').write(data)
    print(f'{src}: {frames} frames, {len(data)} bytes')
