#!/usr/bin/env python3
"""Export three captioned Hotbar demos from an actual screen recording."""
import argparse
import json
from pathlib import Path
import subprocess
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('recording', type=Path)
parser.add_argument('--output', type=Path, default=Path('build/demo-videos'))
args = parser.parse_args()
probe = json.loads(subprocess.check_output([
    'ffprobe', '-v', 'error', '-show_entries', 'format=duration', '-of', 'json', str(args.recording)
]))
if float(probe['format']['duration']) < 30:
    parser.error('Use a recording of at least 30 seconds with the switcher opening, selection and arrangement.')
args.output.mkdir(parents=True, exist_ok=True)
variants = [('website', 1920, 1080, 25), ('social', 1280, 720, 15), ('vertical', 1080, 1920, 30)]

def timestamp(seconds):
    return f'0:{int(seconds) // 60:02}:{int(seconds) % 60:02}.00'

for name, width, height, duration in variants:
    vertical = name == 'vertical'
    font_size = 46 if vertical else int(height * 0.044)
    margin = 160 if vertical else int(height * 0.09)
    captions = [
        (0, 5, 'Hotbar｜ウィンドウ操作を、もっと軽く。'),
        (5, 10, '⌥ Tab で一覧。目的のウィンドウへ。'),
        (10, duration - 3, '左右に配置。作業スペースを整える。'),
        (duration - 3, duration, '14日間、無料で試す。'),
    ]
    ass = f'''[Script Info]
ScriptType: v4.00+
PlayResX: {width}
PlayResY: {height}
WrapStyle: 0
[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: Default,Hiragino Sans,{font_size},&H00FFFFFF,&H00FFFFFF,&H0018100C,&H8018100C,-1,0,0,0,100,100,0,0,3,14,0,2,50,50,{margin},1
[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
'''
    ass += ''.join(f'Dialogue: 0,{timestamp(start)},{timestamp(end)},Default,,0,0,0,,{text}\n'
                   for start, end, text in captions if end > start)
    with tempfile.TemporaryDirectory(prefix='hotbar-video-') as directory:
        subtitle = Path(directory) / 'captions.ass'
        subtitle.write_text(ass)
        # Keep all controls visible, including in portrait; use padding rather than cropping the app.
        usable_height = 1050 if vertical else int(height * 0.78)
        usable_width = int(width * 0.94)
        filters = (
            f'scale={usable_width}:{usable_height}:force_original_aspect_ratio=decrease:force_divisible_by=2,'
            f'pad={width}:{height}:(ow-iw)/2:(oh-ih)/2:color=0x0c1018,'
            f'subtitles={subtitle},fps=30,format=yuv420p'
        )
        subprocess.run([
            'ffmpeg', '-hide_banner', '-y', '-i', str(args.recording), '-t', str(duration),
            '-vf', filters, '-an', '-c:v', 'libx264', '-crf', '20', '-preset', 'medium',
            '-movflags', '+faststart', str(args.output / f'hotbar-{name}.mp4')
        ], check=True)
    print(f'Created {args.output / f"hotbar-{name}.mp4"}')
