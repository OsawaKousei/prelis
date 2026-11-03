"""Verify the known two-tone fixture in the audio actually captured from the app."""

from array import array
import math
from pathlib import Path
import sys
import wave


def analyze(path):
    with wave.open(str(path), 'rb') as audio:
        if (audio.getnchannels(), audio.getsampwidth(), audio.getframerate()) != (1, 2, 16000):
            raise ValueError('Expected 16 kHz mono PCM16 captured audio')
        samples = array('h', audio.readframes(audio.getnframes()))
    if sys.byteorder != 'little':
        samples.byteswap()
    block_size = 800
    blocks = []
    for offset in range(0, len(samples) - block_size + 1, block_size):
        block = samples[offset:offset + block_size]
        energy = sum((value / 32768) ** 2 for value in block)
        rms = math.sqrt(energy / block_size)
        scores = {}
        for frequency in (660, 880):
            coefficient = 2 * math.cos(2 * math.pi * frequency / 16000)
            previous = before = 0.0
            for value in block:
                current = value / 32768 + coefficient * previous - before
                before, previous = previous, current
            power = previous * previous + before * before - coefficient * previous * before
            scores[frequency] = 2 * power / (block_size * energy) if energy else 0
        tone = max(scores, key=scores.get) if rms >= 0.003 and max(scores.values()) >= 0.55 else None
        blocks.append({'start': offset / 16000, 'end': (offset + block_size) / 16000, 'rms': rms, 'tone': tone})
    runs = []
    for block in blocks:
        if runs and runs[-1]['tone'] == block['tone']:
            runs[-1]['end'] = block['end']
        else:
            runs.append({key: block[key] for key in ('start', 'end', 'tone')})
    tones = [run for run in runs if run['tone'] is not None and run['end'] - run['start'] >= 0.099]
    pairs = []
    for first, second in zip(tones, tones[1:]):
        if first['tone'] == 660 and second['tone'] == 880 and 0 <= second['start'] - first['end'] <= 0.3:
            pairs.append({'start': first['start'], 'end': second['end']})
    return {'duration_seconds': len(samples) / 16000, 'two_tone_matches': pairs, 'blocks': blocks}


def verify_capture(directory, report):
    results = []
    for name in ('timer-preview', 'timer-completion'):
        matches = [item for item in report['segments'] if item['name'] == name]
        if len(matches) != 1:
            raise ValueError(f'Expected one {name} recording')
        segment = matches[0]
        media = segment['media']
        if media['audio_tracks'] < 1 or not media.get('pcm_file'):
            raise ValueError(f'{name}: no captured app audio track')
        data = analyze(Path(directory) / media['pcm_file'])
        markers = segment['markers']
        origin = markers['preview-request' if name == 'timer-preview' else 'timer-start-request']
        minimum = origin if name == 'timer-preview' else origin + 58
        maximum = origin + (12 if name == 'timer-preview' else 75)
        tones = [pair for pair in data['two_tone_matches'] if minimum - 0.2 <= pair['start'] <= maximum]
        if not tones:
            raise ValueError(f'{name}: recorded audio does not contain the expected 660 Hz -> 880 Hz fixture at the expected time')
        result = {'name': name, 'status': 'passed', 'matches': tones, 'pcm_file': media['pcm_file']}
        if name == 'timer-completion':
            reset = markers['timer-reset']
            quiet = [block for block in data['blocks'] if block['start'] >= reset + 0.3]
            if len(quiet) < 15 or max(block['rms'] for block in quiet) > 0.003:
                raise ValueError('Timer reset did not stop the captured app audio')
            result['reset_silence_seconds'] = len(quiet) * 0.05
        results.append(result)
    return {'status': 'passed', 'checks': results}
