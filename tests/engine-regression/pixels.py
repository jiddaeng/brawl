# PNG 를 색 보정 없이 RGBA 원본 바이트로 풀어 저장한다 (브라우저 canvas 와 같은 결과인지 확인용)
import sys, PIL.Image as I
for src, dst in zip(sys.argv[1::2], sys.argv[2::2]):
    im = I.open(src); print(src, im.mode, im.info.get('icc_profile') is not None, im.info.get('gamma'), im.info.get('srgb'), file=sys.stderr)
    im = im.convert('RGBA'); open(dst, 'wb').write(im.tobytes()); print(dst, im.size[0], im.size[1])
