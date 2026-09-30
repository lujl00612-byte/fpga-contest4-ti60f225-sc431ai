"""Keep every panel write; shorten delay-only ROM rows for an AXI simulation."""
import hashlib
import json
import re
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
source = REPO / 'projects/mipi_diag/Panel_1080p_reg.mem'
cache = REPO / '.cache'
cache.mkdir(exist_ok=True)
words = []
for line in source.read_text(encoding='utf-8-sig').splitlines():
    word = line.split('//', 1)[0].strip()
    if word:
        assert re.fullmatch(r'[0-9a-fA-F]{10}', word), word
        words.append(int(word, 16))
assert len(words) == 169 and len(words) < 180
assert all(word != 0 for word in words)
writes = [word for word in words if word >> 32]
assert len(writes) == 119
fixture = [word if word >> 32 else 3 for word in words]
# The Efinix RAM template documents zero initialization of unspecified rows.
# Icarus leaves them X without explicit padding, so the fixture includes zeros.
fixture += [0] * (512 - len(fixture))
rom = cache / 'panel_axi_fixture.mem'
expected = cache / 'panel_axi_expected.mem'
rom.write_text(''.join(f'{word:010X}\n' for word in fixture), encoding='ascii')
expected.write_text(''.join(f'{word:010X}\n' for word in writes), encoding='ascii')
# Two externally identical write/read sequences, differing only in delay bit
# 22. The expected second-write time difference is exactly 2**22 clocks.
for name, delay in [('short', 8), ('long', (1 << 22) + 8)]:
    values = [0x2000001105, delay, 0x2000002905] + [0]*509
    (cache / f'panel_delay_{name}.mem').write_text(
        ''.join(f'{word:010X}\n' for word in values), encoding='ascii')
report = {
    'source': source.relative_to(REPO).as_posix(),
    'source_sha256': hashlib.sha256(source.read_bytes()).hexdigest().upper(),
    'source_words': len(words), 'write_transactions': len(writes),
    'shortened_delay_rows': [i for i, word in enumerate(words) if word >> 32 == 0],
    'simulation_delay_value': 3, 'zero_padding_words': 512-len(words),
    'fixture_sha256': hashlib.sha256(rom.read_bytes()).hexdigest().upper(),
    'expected_write_list_sha256': hashlib.sha256(expected.read_bytes()).hexdigest().upper(),
    'legacy_22_bit_truncations': [
        {'rom_index': i, 'requested_clocks': word & 0xffffffff,
         'truncated_clocks': word & ((1 << 22)-1)}
        for i, word in enumerate(words) if word >> 32 == 0 and word >= 1 << 22],
    'scope': 'AXI order, payload, status polling, stalls, reset only; physical delay durations and DSI PHY are not simulated.'
}
(cache / 'panel_fixture.json').write_text(json.dumps(report, indent=2)+'\n', encoding='utf-8')
print(f'Prepared panel fixture: {len(writes)} exact writes, {len(report["shortened_delay_rows"])} shortened delays; physical delays unverified')
