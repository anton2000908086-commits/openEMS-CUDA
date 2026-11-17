"""Benchmark model for openEMS CPU vs GPU: python bench_model.py N STEPS [out.xml]
N cells per side (1 mm), PML_8 on all faces, copper sheet, source in the centre, two voltage probes."""
import sys
n = int(sys.argv[1]) if len(sys.argv) > 1 else 100
steps = int(sys.argv[2]) if len(sys.argv) > 2 else 2000
out = sys.argv[3] if len(sys.argv) > 3 else "bench.xml"
c = n // 2
lines = ",".join(map(str, range(n)))
xml = f'''<?xml version="1.0"?>
<openEMS>
  <FDTD NumberOfTimesteps="{steps}" endCriteria="1e-6">
    <Excitation Type="0" f0="2.5e9" fc="2.5e9"/>
    <BoundaryCond xmin="PML_8" xmax="PML_8" ymin="PML_8" ymax="PML_8" zmin="PML_8" zmax="PML_8"/>
  </FDTD>
  <ContinuousStructure CoordSystem="0">
    <RectilinearGrid DeltaUnit="0.001" CoordSystem="0">
      <XLines>{lines}</XLines>
      <YLines>{lines}</YLines>
      <ZLines>{lines}</ZLines>
    </RectilinearGrid>
    <Properties>
      <ConductingSheet ID="3" Name="cu" Conductivity="5.8e7" Thickness="3.5e-5">
        <Primitives><Box Priority="10"><P1 X="{c-10}" Y="{c-8}" Z="{c+4}"/><P2 X="{c+10}" Y="{c+8}" Z="{c+4}"/></Box></Primitives>
      </ConductingSheet>
      <Excitation ID="0" Name="exc" Number="0" Type="0" Excite="0,0,1">
        <Primitives><Box Priority="0"><P1 X="{c}" Y="{c}" Z="{c-4}"/><P2 X="{c}" Y="{c}" Z="{c-3}"/></Box></Primitives>
      </Excitation>
      <ProbeBox ID="1" Name="ut_near" Number="0" Type="0" Weight="1">
        <Primitives><Box Priority="0"><P1 X="{c+2}" Y="{c}" Z="{c-4}"/><P2 X="{c+2}" Y="{c}" Z="{c-3}"/></Box></Primitives>
      </ProbeBox>
      <ProbeBox ID="2" Name="ut_far" Number="0" Type="0" Weight="1">
        <Primitives><Box Priority="0"><P1 X="{c+9}" Y="{c}" Z="{c-4}"/><P2 X="{c+9}" Y="{c}" Z="{c-3}"/></Box></Primitives>
      </ProbeBox>
    </Properties>
  </ContinuousStructure>
</openEMS>
'''
open(out, "w").write(xml)
print("wrote", out)
