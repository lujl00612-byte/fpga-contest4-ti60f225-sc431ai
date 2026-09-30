"""Verify offline WB03 top-level wiring, timing constants and GPIO profile."""
import argparse
import hashlib
import json
import re
from pathlib import Path
import xml.etree.ElementTree as ET

REPO = Path(__file__).resolve().parents[1]
PROJECT = REPO / 'projects/mipi_diag'


def ports_of(text, name):
    start = text.index('  ' + name + ' (')
    end = start + re.search(r'\n\s*\);', text[start:]).start()
    return dict(re.findall(r'\.([A-Za-z0-9_]+)\s*\(\s*([^()]*)\s*\)', text[start:end]))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    top = (PROJECT / 'rtl/ti60f225_oob_top.v').read_text(encoding='utf-8-sig')
    root = ET.parse(PROJECT / 'ti60f225_oob.peri.xml').getroot()
    gpios = {node.get('name'): dict(node.attrib) for node in root.iter()
             if node.tag.rsplit('}', 1)[-1] == 'comp_gpio'}
    assert len({gpio['gpio_def'] for gpio in gpios.values()}) == len(gpios), 'Duplicate GPIO assignments'
    for name, pin, mode in [('i_arstn', 'GPIOL_07', 'input'),
                            ('led[0]', 'GPIOR_27', 'output'), ('led[1]', 'GPIOR_24', 'output')]:
        assert gpios[name]['gpio_def'] == pin and gpios[name]['mode'] == mode
        assert gpios[name]['io_standard'] == '3.3 V LVCMOS'
    assert all(not name.startswith('color_keys') for name in gpios)
    assert all(name in ('led[0]', 'led[1]') for name in gpios if name.startswith('led['))
    assert 'screen_color_control' not in top and 'video_white_balance' not in top
    source = (PROJECT / 'rtl/mipi_diagnostic_rgb2.v').read_text(encoding='utf-8')
    assert 'rgb_at(x1,y), rgb_at(x0,y)' in source and '64\'d0' in source
    channels = []
    for i in range(2):
        enable = 'pixel_data_en' + ('1' if i else '')
        ports = {key: value.strip() for key, value in ports_of(top, f'dsi_tx_top_inst{i+1}').items()}
        for port, suffix in [('pixel_vs_i', 'vs'), ('pixel_hs_i', 'hs'),
                             ('pixel_de_i', 'de'), ('pixel_data_i', 'pixels')]:
            assert ports[port] == f'diag{i}_{suffix}', (i, port)
        assert ports['pixel_data_en'] == enable
        block = re.search(r'\) diag'+str(i)+r' \((.*?)\);', top, re.S)[1]
        assert f'.enable_i({enable})' in block
        assert '.rst_n(w_arstn)' in block and '.clk(vid_clk_dvi2)' in block
        channels.append({'channel': i, 'enable': enable, 'pixel_ports': ports})
    assert re.search(r'output\s+\[1:0\]\s+led', top)
    timing = dict((key, int(value)) for key, value in re.findall(
        r'localparam\s+(MAX_HRES|MAX_VRES|HSP|HBP|HFP|VSP|VBP|VFP)\s*=\s*\d+\'d(\d+)', top))
    assert timing == {'MAX_HRES': 1920, 'MAX_VRES': 1080, 'HSP': 4, 'HBP': 88,
                      'HFP': 120, 'VSP': 2, 'VBP': 20, 'VFP': 20}
    frame_clocks = (1920+4+88+120)//2 * (1080+2+20+20)
    sdc = (PROJECT / 'ti60f225_oob.sdc').read_text(encoding='utf-8-sig')
    clock = next(line for line in sdc.splitlines() if line.startswith('create_clock ') and 'vid_clk_dvi2' in line)
    period_ns = float(re.search(r'-period\s+(\S+)', clock)[1])
    original = REPO / 'projects/mipi/Panel_1080p_reg.mem'
    candidate = PROJECT / 'Panel_1080p_reg.mem'
    assert candidate.read_bytes() == original.read_bytes(), 'Panel write table or hardware delays changed'
    controller = (PROJECT / 'rtl/mipi_config/panel_config.v').read_text(encoding='utf-8')
    assert re.search(r'reg\s+\[31:0\]\s*r_timer', controller), 'Panel delay counter loses high bits'
    assert 'r_timer == w_reg[31:0]' in controller, 'Panel delay comparison loses high bits'
    for line in (PROJECT / 'all_sources.f').read_text(encoding='utf-8').splitlines():
        local = REPO / line.replace('\\', '/').removeprefix('H:/')
        assert local.is_file(), line
        assert 'projects/mipi_diag/' in line.replace('\\', '/')
    report = {'status': 'PASS', 'timing': timing, 'two_pixel_words_per_line': 1066,
              'lines_per_frame': 1122, 'frame_clocks': frame_clocks,
              'constrained_pixel_clock_period_ns': period_ns,
              'derived_frame_rate_hz': 1e9/(period_ns*frame_clocks),
              'panel_table_sha256': hashlib.sha256(candidate.read_bytes()).hexdigest().upper(),
              'panel_delay_counter_bits': 32,
              'DSI_channels': channels, 'GPIO_count': len(gpios),
              'board_profile': json.loads((PROJECT / 'diagnostic-profile.json').read_text(encoding='utf-8')),
              'physical_video_validation': 'pending',
              'scope': 'Static connections and source constants; encrypted DSI PHY, measured clocks, PCB identity and visible RGB order remain unverified.'}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    print(f'PASS WB03 integration: 2 independent DSI enables; {frame_clocks} clocks/frame; {report["derived_frame_rate_hz"]:.4f} Hz from SDC (not a measurement)')


if __name__ == '__main__':
    main()
