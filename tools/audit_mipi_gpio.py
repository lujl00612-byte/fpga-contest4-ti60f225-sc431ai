"""Compare local project GPIO with the supplied V4 Key Demo, without touching hardware."""
import argparse
import hashlib
import json
from pathlib import Path
import xml.etree.ElementTree as ET

REPO = Path(__file__).resolve().parent.parent
REFERENCE = (REPO.parents[1] / 'Ti60F225_DemoBoard_v4完整资料包' /
             'Ti60F225_DemoBoard_v4' / '01_Ti60F225_Key_led_osc_demo' /
             '01_Ti60F225_key_demo' / 'LED_8bit_Test.peri.xml')


def profile(path):
    raw = path.read_bytes()
    ports = [dict(node.attrib) for node in ET.fromstring(raw).iter()
             if node.tag.rsplit('}', 1)[-1] == 'comp_gpio']
    return {'path': str(path), 'sha256': hashlib.sha256(raw).hexdigest().upper(),
            'ports': ports}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--reference', type=Path, default=REFERENCE)
    parser.add_argument('--project', type=Path, default=REPO / 'projects/mipi')
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    current = profile(args.project / 'ti60f225_oob.peri.xml')
    reference = profile(args.reference)
    by_pin = {port['gpio_def']: port for port in reference['ports']}
    conflicts, shared_inputs = [], []
    for port in current['ports']:
        other = by_pin.get(port['gpio_def'])
        if not other:
            continue
        row = {'gpio': port['gpio_def'], 'current': port, 'V4_key_demo': other}
        if port['mode'] != other['mode']:
            conflicts.append(row)
        elif port['mode'] == 'input' and port['name'].startswith('color_keys'):
            shared_inputs.append(row)
    report = {'current_profile': current, 'V4_reference': reference,
              'direction_conflicts': conflicts, 'shared_key_inputs': shared_inputs,
              'actual_PCB_version_confirmed': False,
              'hardware_levels_measured': False,
              'GPIO_cause_of_no_image_confirmed': False,
              'scope': 'Offline profile comparison only; no programming or GPIO access.'}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(f'Offline GPIO audit: {len(conflicts)} direction conflicts, '
          f'{len(shared_inputs)} shared key inputs; PCB and levels remain unverified')


if __name__ == '__main__':
    main()
