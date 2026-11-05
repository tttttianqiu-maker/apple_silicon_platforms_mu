/**
 * T8122 (Apple M3, base) MMIO windows for the UEFI page tables.
 *
 * Derived from Asahi Linux arch/arm64/boot/dts/apple/t8122.dtsi (every device
 * "reg" clustered into windows). UNVERIFIED ON HARDWARE: check against the
 * ADT dump of a real J613 before trusting it.
 *
 * Core system MMIO must be mapped nGnRnE, PCIe MMIO nGnRE (see MemoryInitPeiLib).
 **/
#include <Base.h>
#ifndef APPLE_VIRTUAL_MEMORY_MAP_DEFINES_H_
#define APPLE_VIRTUAL_MEMORY_MAP_DEFINES_H_

typedef struct { UINT64 Base; UINT64 Size; } APPLE_MMIO_WINDOW;

// cpufreq, pmgr, AIC3, DCP, I2C/SPI/UART, MTP + DockChannel, AOP ... (0x2_0000_0000 - 0x2_FFFF_FFFF)
// ANS/NVMe, SART, DCP-ext (0x3_0000_0000 - 0x3_1FFF_FFFF)
// PCIe root complex regs (0x5_8000_0000), USB4/Thunderbolt + USB (0x7_0100_0000, 0xB_0100_0000)
#define APPLE_CORE_SYSTEM_MMIO_WINDOWS { \
  { 0x200000000ULL, SIZE_2GB   }, \
  { 0x280000000ULL, SIZE_2GB   }, \
  { 0x300000000ULL, SIZE_512MB }, \
  { 0x580000000ULL, SIZE_512MB }, \
  { 0x700000000ULL, SIZE_64MB  }, \
  { 0xB00000000ULL, SIZE_64MB  }, \
  /* vGIC emulated by m1n1_windows (hv_vgic.c *_42_BIT, enabled for T8122) */ \
  { 0x5000000000ULL, SIZE_64KB }, /* GICD */ \
  { 0x5100000000ULL, SIZE_2MB  }, /* GICR, 8 cpus */ \
  { 0x5200000000ULL, SIZE_2MB  }, /* ITS (unused) */ \
}

// From pcie0 "ranges": 64-bit prefetchable 0x5_A000_0000 (512MB), 32-bit 0x5_C000_0000 (1GB)
#define APPLE_PCIE_MMIO_WINDOWS { \
  { 0x5A0000000ULL, SIZE_512MB }, \
  { 0x5C0000000ULL, SIZE_1GB   }, \
}

// TODO(j613): M1 hardcodes DRAM at 0x8_0000_0000. On M3 take it from the ADT
// "dram-base" property that m1n1 passes along; do NOT assume the M1 value.

#endif
