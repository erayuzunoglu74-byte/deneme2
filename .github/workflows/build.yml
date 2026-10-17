name: Build VortexOS
on: workflow_dispatch
jobs:
  build:
    runs-on: ubuntu-latest
    strategy:
      fail-fast: false
      matrix:
        target: ["64", "32"]
    container:
      image: debian:bookworm
      options: --privileged
    steps:
      - name: Hazirlik
        run: apt-get update && apt-get install -y git ca-certificates
      - uses: actions/checkout@v4
      - name: ISO derle
        run: |
          chmod +x vortexos-build.sh
          ./vortexos-build.sh ${{ matrix.target }}
      - uses: actions/upload-artifact@v4
        with:
          name: vortexos-${{ matrix.target }}bit
          path: output/*.iso
