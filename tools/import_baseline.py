"""Preserve the existing releases before starting the new Git iterations."""
from pathlib import Path
import shutil
import subprocess
import xml.etree.ElementTree as ET

repo = Path(__file__).resolve().parents[1]
old = repo.parent / 'Ti60f225_sc431hai2hdmi_v6'
vendor = repo.parent.parent / 'tmp/vendor_dsi_20260930/Ti60f225_csi2dsi_sc431hai_v3.5'


def copy_project(src, dst):
    dst.mkdir(parents=True, exist_ok=True)
    for folder in ('rtl', 'ip'):
        shutil.copytree(src / folder, dst / folder, dirs_exist_ok=True)
    for file in src.iterdir():
        if file.is_file() and file.suffix in ('.xml', '.sdc', '.mem', '.memh', '.v', '.f', '.json'):
            shutil.copy2(file, dst / file.name)
    ns = {'efx': 'http://www.efinixinc.com/enf_proj'}
    xml = ET.parse(dst / 'ti60f225_oob.xml')
    files = [x.attrib['name'] for x in xml.findall('.//efx:design_file', ns)]
    for ip in xml.findall('.//efx:ip', ns):
        files.extend(str(Path(ip.attrib['path']).parent / x.attrib['name'])
                     for x in ip.findall('efx:ip_src_file', ns))
    relative = dst.relative_to(repo)
    flist = [str(Path('H:/') / relative / file) for file in files]
    (dst / 'all_sources.f').write_text('\n'.join(flist) + '\n', encoding='utf-8')


entries = [
    ('V1', 'contest4_versions/V1_complete_baseline', 'V1_complete_baseline'),
    ('V2', 'contest4_versions/V2_complete_denoise', 'V2_complete_gaussian'),
    ('V3', 'contest4_versions/V3_complete_adaptive', 'V3_complete_adaptive'),
    ('A1', 'contest4_advanced/A1_median_color_overlay', 'A1_median_color_overlay'),
    ('A2', 'contest4_advanced/A2_canny_color_overlay', 'A2_canny_color_overlay'),
    ('A3', 'contest4_advanced/A3_canny_freeze_shape', 'A3_all_advanced_integrated'),
    ('A4', 'contest4_advanced/A4_median_pipeline', 'A4_median_pipeline'),
    ('A5', 'contest4_advanced/A5_shape_pipeline', 'A5_shape_pipeline'),
    ('A6', 'contest4_advanced/A6_corner_pipeline', 'A6_corner_pipeline'),
]
for tag, src, release in entries:
    copy_project(old / src, repo / 'snapshots' / tag)
    shutil.copytree(old / 'contest4_releases' / release, repo / 'releases' / tag,
                    dirs_exist_ok=True)
    subprocess.run(['git', 'add', '.gitignore', 'tools/import_baseline.py',
                    f'snapshots/{tag}', f'releases/{tag}'], cwd=repo, check=True,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(['git', 'commit', '-qm', f'Archive verified legacy {tag} source and release'],
                   cwd=repo, check=True)
    subprocess.run(['git', 'tag', f'legacy-{tag}'], cwd=repo, check=True)
copy_project(old / entries[-1][1], repo / 'projects/hdmi')
copy_project(vendor, repo / 'projects/mipi')
dst = repo / 'releases/vendor-mipi-3.5'
dst.mkdir(parents=True, exist_ok=True)
for suffix in ('.bit', '.hex'):
    shutil.copy2(vendor / 'outflow' / ('ti60f225_oob' + suffix), dst / ('vendor_color' + suffix))
shutil.copy2(old / 'contest4_releases/A6_corner_pipeline/jtag_load_sram.py', repo / 'tools/jtag_load_sram.py')
subprocess.run(['git', 'add', 'projects', 'releases/vendor-mipi-3.5', 'tools'], cwd=repo, check=True,
               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
subprocess.run(['git', 'commit', '-qm', 'Establish A6 HDMI and original 3.5 inch MIPI working baselines'],
               cwd=repo, check=True)
subprocess.run(['git', 'tag', 'baseline-20260930'], cwd=repo, check=True)
print('Imported V1-V3, A1-A6, original MIPI source and releases; 10 Git checkpoints.')
