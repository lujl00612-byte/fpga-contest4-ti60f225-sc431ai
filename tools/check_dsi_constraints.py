"""Check that the bundled Ti60F225 DSI clock-lane exception applies to this build."""
import hashlib
import json
import re
from pathlib import Path
import xml.etree.ElementTree as ET

repo = Path(__file__).resolve().parents[1]
project = repo / "projects/mipi"
reference = (repo.parent / "efinity2025_clean/PFiles/Efinity/2025.1/ipm/ip/efx_dsi"
             / "fpga/constraint/ti60f225_demo.sdc")
reference_hash = hashlib.sha256(reference.read_bytes()).hexdigest().upper()
assert reference_hash == "C7E778BF1CAEF44C56EE0E38F16C8F5C3ED1D7006425A6BDF4DB83C1542AE745", "Vendor reference changed; review before using its exception"
sdc = project.joinpath("ti60f225_oob.sdc").read_text(encoding="utf-8-sig")
ref_sdc = reference.read_text()
clocks = {"i_mipi_tx_pclk": (8.0, 0.0), "i_mipi_txd_sclk": (2.0, 0.5),
          "i_mipi_txc_sclk": (2.0, 1.0)}
for text in (sdc, ref_sdc):
    for name, (period, phase) in clocks.items():
        line = next(line for line in text.splitlines() if line.startswith("create_clock ") and name in line)
        assert float(re.search(r"-period\s+(\S+)", line)[1]) == period, name
        waveform = re.search(r"-waveform\s+\{([\d.]+)\s+[\d.]+\}", line)
        assert (float(waveform[1]) if waveform else 0.0) == phase, name

ns = {"p": "http://www.efinixinc.com/peri_design"}
root = ET.parse(project / "ti60f225_oob.peri.xml").getroot()
# Take the actual namespace from the file rather than depending on schema revision.
ns["p"] = root.tag[1:].split("}")[0]
pll = root.find(".//p:pll[@name='MIPI_TX_PLL']", ns)
for name, divider, phase in (("i_mipi_tx_pclk", "16", "0"), ("i_mipi_txd_sclk", "4", "2"), ("i_mipi_txc_sclk", "4", "4")):
    output = pll.find(f"p:comp_output_clock[@name='{name}']", ns)
    assert output.get("out_divider") == divider and output.get("phase_setting") == phase, name
    assert output.get("is_dyn_phase") == "false" and output.get("is_inverted") == "false", name
for lane in ("mipi_dp_clk", "mipi_dp_clk1"):
    tx = root.find(f".//p:mipi_dphy[@name='{lane}']/p:tx_info", ns)
    pins = {pin.get("type_name"): pin.get("name") for pin in tx.findall("p:gen_pin/p:pin", ns)}
    assert tx.get("mode") == "clock lane" and pins["SLOWCLK"] == "i_mipi_txd_sclk" and pins["FASTCLK"] == "i_mipi_txc_sclk", lane
conf = json.loads(project.joinpath("ip/dsi_tx/settings.json").read_text())["conf"]
assert conf["HS_BYTECLK_MHZ"] == "125" and conf["DPHY_CLOCK_MODE"] == '"Continuous"'
exceptions = [line for line in sdc.splitlines() if line.startswith("set_multicycle_path ")]
assert len(exceptions) == 2, "Review added multicycle exceptions"
for cycles, kind, line in zip((3, 2), ("setup", "hold"), exceptions):
    assert line == (f"set_multicycle_path {cycles} -{kind} -from [get_clocks {{i_mipi_tx_pclk}}] "
                    "-to [get_ports {mipi_dp_clk_HS_OUT[*] mipi_dp_clk1_HS_OUT[*]}] -end"), line
    assert f"set_multicycle_path {cycles} -{kind} -to [get_ports mipi_dp_clk_HS_OUT[*]] -end" in ref_sdc
print(json.dumps({"status": "PASS", "vendor_reference": str(reference),
                  "vendor_reference_sha256": reference_hash, "clock_period_phase_ns": clocks,
                  "exception_scope": exceptions, "setup_edge_ns_before": 0.5,
                  "setup_edge_ns_after": 4.5, "hold_edge_ns_before_and_after": -1.5,
                  "scope_limit": "Constraint adoption from matching vendor example; not a panel waveform or encrypted IP functional simulation"}, indent=2))
