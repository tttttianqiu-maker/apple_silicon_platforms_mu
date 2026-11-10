/**
 * Copyright (c) 2023, amarioguy (AppleWOA authors).
 * 
 * Module Name:
 *     DSDT.asl
 * 
 * Abstract:
 *     Differentiated System Description Table. This source file implements the DSDT table
 *     for the MacBook Air (Mid 2020) platform.
 * 
 * Environment:
 *     UEFI firmware/runtime services.
 * 
 * License:
 *     SPDX-License-Identifier: BSD-2-Clause-Patent OR MIT
 * 
 **/
#include <IndustryStandard/Acpi65.h>

 DefinitionBlock("DSDT.aml", "DSDT", 0x02, "Apple", "J613", 0x8122) {
    Scope(\_SB) {
        //
        // Built-in keyboard + trackpad (J613 has no SPI HID; input is MTP ->
        // DockChannel HID). m1n1 owns the MTP coprocessor, DockChannel, the
        // trackpad firmware and SMC GPIO power sequencing (m1n1 hv_dchid.c) and
        // exposes the HID reports as the "AVHD" virtual device: one 4 KiB
        // trapped MMIO page and one edge-triggered virtual SPI. m1n1 always
        // backs the page on T8122; STATUS reads 0 if the MTP did not come up.
        // Driver: drivers/apple-input/windows/AppleMtpInput.inf (ACPI\APPL0613).
        // Must match HV_AVHD_IPA / HV_AVHD_GSIV in m1n1_windows/src/hv_dchid.h.
        //
        // _UID is the Windows device instance ID (ACPI\APPL0613\<UID>). Windows
        // Setup enumerated ACPI\APPL0613\0 before AppleMtpInput existed and
        // left it at Code 28 (no driver); a driver staged offline later (DISM)
        // is not retried on that devnode. A new _UID is new hardware to PnP,
        // which then installs the staged driver by itself (EXP-20261110-054).
        Device(AVHD) {
            Name(_HID, "APPL0613")
            Name(_UID, 0x613)
            Name(_STA, 0x0F)
            Name(_CRS, ResourceTemplate() {
                QWordMemory(ResourceConsumer, PosDecode, MinFixed, MaxFixed, NonCacheable, ReadWrite,
                    0x0000000000000000, 0x0000005300000000, 0x0000005300000FFF,
                    0x0000000000000000, 0x0000000000001000)
                Interrupt(ResourceConsumer, Edge, ActiveHigh, Exclusive) { 65 }
            })
        }

        //
        // Battery + AC adapter (m1n1 hv_battery.c, `j613 battery on`): m1n1 reads
        // the SMC battery keys read-only (as Linux macsmc-power) and serves them
        // in the AVHD page at +0x100 (layout: m1n1_windows/src/dchid_proto.h
        // DCHID_BATT_*). Windows' inbox cmbatt.sys drives PNP0C0A. BFLG bit 0
        // clear (battery off, or an m1n1 without it: the page reads 0 there)
        // hides both devices.
        //
        OperationRegion(BATR, SystemMemory, 0x0000005300000100, 0x30)
        Field(BATR, DWordAcc, NoLock, Preserve) {
            BMAG, 32,   // "BATT"
            BFLG, 32,   // bit0 present, 1 AC, 2 charging, 3 discharging, 4 critical
            BDCP, 32,   // design capacity, mAh
            BFCP, 32,   // last full charge capacity, mAh
            BRCP, 32,   // remaining capacity, mAh
            BRAT, 32,   // present rate, mA
            BVOL, 32,   // present voltage, mV
            BCYC, 32,   // cycle count
            BDVO, 32,   // design voltage, mV
            BPCT, 32,   // percent
            BSEQ, 32,   // refresh counter
            BEVT, 32,   // read-to-clear: bit0 _BST, bit1 AC, bit2 _BIX changed
        }

        Device(BAT0) {
            Name(_HID, EisaId("PNP0C0A"))
            Name(_UID, One)
            Name(_PCL, Package() { \_SB })
            Method(_STA, 0, Serialized) {
                If (BFLG & 1) {
                    Return (0x1F)
                }
                Return (Zero)
            }
            //
            // Windows wants milliwatts (Microsoft "ACPI battery and power subsystem
            // firmware implementation": _BIX revision 0, power unit 0, serial not
            // empty, accuracy >= 95 %). m1n1 serves mA/mAh; everything is scaled
            // by the design voltage, so percentages and time estimates stay
            // exact. Each register is read once per method (every read traps).
            //
            Method(_BIX, 0, Serialized) {
                Name(BIXP, Package(20) {
                    Zero,           // revision 0
                    Zero,           // power unit: mW / mWh
                    Zero,           // design capacity
                    Zero,           // last full charge capacity
                    One,            // rechargeable
                    Zero,           // design voltage, mV
                    Zero,           // design capacity of warning
                    Zero,           // design capacity of low
                    Zero,           // cycle count
                    95000,          // measurement accuracy, 95 %
                    60000,          // max sampling time, ms (m1n1 reads every 60 s)
                    60000,          // min sampling time, ms
                    0xFFFFFFFF,     // max averaging interval: unknown
                    0xFFFFFFFF,     // min averaging interval: unknown
                    One,            // granularity 1, mWh
                    One,            // granularity 2, mWh
                    "MacBook Air",  // model
                    "J613",         // serial
                    "LION",         // type
                    "Apple"         // OEM
                })
                Local0 = BDVO
                Local1 = (BDCP * Local0) / 1000
                BIXP[2] = Local1
                BIXP[3] = (BFCP * Local0) / 1000
                BIXP[5] = Local0
                BIXP[6] = (Local1 * 7) / 100
                BIXP[7] = (Local1 * 3) / 100
                Local2 = BCYC
                If (Local2 == 0xFFFFFFFF) {
                    Local2 = Zero
                }
                BIXP[8] = Local2
                Return (BIXP)
            }
            Method(_BIF, 0, Serialized) {
                Name(BIFP, Package(13) {
                    Zero, Zero, Zero, One, Zero, Zero, Zero, One, One,
                    "MacBook Air", "J613", "LION", "Apple"
                })
                Local0 = _BIX()
                BIFP[0] = DerefOf(Local0[1])
                BIFP[1] = DerefOf(Local0[2])
                BIFP[2] = DerefOf(Local0[3])
                BIFP[4] = DerefOf(Local0[5])
                BIFP[5] = DerefOf(Local0[6])
                BIFP[6] = DerefOf(Local0[7])
                Return (BIFP)
            }
            Method(_BST, 0, Serialized) {
                Name(BSTP, Package(4) { Zero, Zero, Zero, Zero })
                Local1 = BFLG
                Local2 = BDVO
                Local0 = Zero
                If (Local1 & 8) {
                    Local0 |= 1     // discharging
                }
                If (Local1 & 4) {
                    Local0 |= 2     // charging
                }
                If (Local1 & 0x10) {
                    Local0 |= 4     // critical
                }
                BSTP[0] = Local0
                Local3 = BRAT
                If (Local3 != 0xFFFFFFFF) {
                    Local3 = (Local3 * Local2) / 1000
                }
                BSTP[1] = Local3
                BSTP[2] = (BRCP * Local2) / 1000
                BSTP[3] = BVOL
                Return (BSTP)
            }
        }

        Device(ADP1) {
            Name(_HID, "ACPI0003")
            Name(_UID, One)
            Name(_PCL, Package() { \_SB })
            Method(_STA, 0, Serialized) {
                If (BFLG & 1) {
                    Return (0x0F)
                }
                Return (Zero)
            }
            Method(_PSR, 0, Serialized) {
                Return ((BFLG >> 1) & 1)
            }
        }

        //
        // Battery change events: ACPI Generic Event Device on edge vSPI 66
        // (m1n1 HV_IRQ_SYNTHETIC_BATT_VINTID; Windows 11 Arm binds ACPI0013 to
        // its inbox ACPI driver). m1n1 raises it after a refresh that changed
        // something; _EVT reads (and clears) BEVT and notifies, so Windows
        // updates the battery icon and the AC state at once instead of polling.
        // Present only while the battery is.
        //
        Device(BGED) {
            Name(_HID, "ACPI0013")
            Name(_UID, One)
            Method(_STA, 0, Serialized) {
                If (BFLG & 1) {
                    Return (0x0F)
                }
                Return (Zero)
            }
            Name(_CRS, ResourceTemplate() {
                Interrupt(ResourceConsumer, Edge, ActiveHigh, Exclusive) { 66 }
            })
            Method(_EVT, 1, Serialized) {
                Local0 = BEVT
                If (Local0 & 2) {
                    Notify(\_SB.ADP1, 0x80)
                }
                If (Local0 & 4) {
                    Notify(\_SB.BAT0, 0x81)
                }
                If (Local0 & 1) {
                    Notify(\_SB.BAT0, 0x80)
                }
            }
        }

        //
        // Cluster low power states. On T8122 there are only 2 clusters, the P and E core clusters,
        // so should be easier to track
        //
        Name (CLPI, Package() {
            0, // Version
            0, // Level Index
            1, // Count
            Package() { // Power Gating state for Cluster
            1, // Min residency (uS)
            1, // Wake latency (uS)
            1, // Flags
            1, // Arch Context Flags
            0, //Residency Counter Frequency
            0, // No Parent State
            0x00000000, // Integer Entry method (currently NULL, TODO actually add an entry method)
            ResourceTemplate() { // Null Residency Counter
                Register (SystemMemory, 0, 0, 0, 0)
            },
            ResourceTemplate() { // Null Usage Counter
                Register (SystemMemory, 0, 0, 0, 0)
            },
            "ClusterRetention"
            },
        })

        //
        // Per processor low power states.
        //
        Name(PLPI, Package() {
            0, // Version
            0, // Level Index
            2, // Count
            Package() { // WFI for CPU
            1, // Min residency (uS)
            1, // Wake latency (uS)
            1, // Flags
            0, // Arch Context Flags
            0, //Residency Counter Frequency
            0, // No parent state
            ResourceTemplate () {
                // Register Entry method
                Register (SystemMemory,
                0x00,               // Bit Width
                0x00,               // Bit Offset
                0x00,         // Address
                0x00,               // Access Size
                )
            },
            ResourceTemplate() { // Null Residency Counter
                Register (SystemMemory, 0, 0, 0, 0)
            },
            ResourceTemplate() { // Null Usage Counter
                Register (SystemMemory, 0, 0, 0, 0)
            },
            "WFI",
            },
            Package() { // Power Gating state for CPU
            1, // Min residency (uS)
            1, // Wake latency (uS)
            1, // Flags
            1, // Arch Context Flags
            0, //Residency Counter Frequency
            1, // Parent node can be in any state
            ResourceTemplate () {
                // Register Entry method
                Register (SystemMemory,
                0x00,               // Bit Width
                0x00,               // Bit Offset
                0x00000000,         // Address
                0x00,               // Access Size
                )
            },
            ResourceTemplate() { // Null Residency Counter
                Register (SystemMemory, 0, 0, 0, 0)
            },
            ResourceTemplate() { // Null Usage Counter
                Register (SystemMemory, 0, 0, 0, 0)
            },
            "CorePwrDn"
            },
        })

        Device(COM0) {
            Name(_HID, "APPL8900") // naming it APPL8900 since the Samsung based UART was used since the 8900
            Name(_UID, Zero)
            Name (_CRS, ResourceTemplate () {
                QWordMemory (
                ResourceProducer,     // ResourceUsage
                PosDecode,            // Decode
                MinFixed,             // IsMinFixed
                MaxFixed,             // IsMaxFixed
                NonCacheable,         // Cacheable
                ReadWrite,            // ReadAndWrite
                0x0000000000000000,   // AddressGranularity - GRA
                //
                // Literals on purpose. Trim.py does substitute the PCD here, but it emits
                // 0x235200000ULL - and iasl understands neither the ULL suffix nor the
                // parenthesised addition that produced the maximum, so the descriptor came
                // out with Min > Max (ASL error 6051). This file is T8122-specific anyway;
                // the value is PcdAppleUartBase from T8122FamilyPkg.dsc.inc.
                //
                0x00000002A1200000,   // AddressMinimum - MIN
                0x00000002A1200FFF,   // AddressMaximum - MAX
                0x0000000000000000,   // AddressTranslation - TRA
                0x0000000000001000    // RangeLength - LEN
                )
                Interrupt(ResourceConsumer, Level, ActiveHigh, Exclusive) { 757 }   /* TODO(j613): AIC 757 from t8122.dtsi; M1 used a non-identity value here, verify */            
            })
            Method (_STA) {
                Return (0xF)
            }
        }

        //
        // The Type-C port not occupied by the m1n1 proxy. AppleUsbTypeCBringupDxe
        // leaves this DWC3 instance in xHCI host mode and its DARTs in bypass, so
        // Windows can bind the inbox USBXHCI driver directly to the standard xHCI
        // register window. Physical AIC 1030 on T8122; m1n1 delivers it as guest INTID 857.
        //
        Device(XHC1) {
            // This DWC3 has no standard xHCI debug capability.  PNP0D10 selects the
            // DebuggerSafe install path and, with KD active, Windows preserves a
            // debugger-owned controller instead of creating the normal xHCI rings.
            // PNP0D15 selects the inbox no-standard-debug path used by the other M1 boards.
            Name(_HID, EISAID("PNP0D15"))
            Name(_UID, One)
            Name(_CCA, One)
            Name(_CRS, ResourceTemplate() {
                QWordMemory(
                    ResourceConsumer, PosDecode, MinFixed, MaxFixed, NonCacheable, ReadWrite,
                    0x0000000000000000, // Granularity
                    0x0000000B02280000, // Min - usb-drd1 / xHCI
                    0x0000000B0237FFFF, // Max
                    0x0000000000000000, // Translation
                    0x0000000000100000  // Length (1 MB)
                )
                Interrupt(ResourceConsumer, Level, ActiveHigh, Exclusive) { 857 }   // guest INTID; m1n1 routes physical AIC 1030 here
            })
            Method(_STA) { Return(0xF) }
        }

        //
        // Emulated PCIe root bridge (host: m1n1 hv_pci.c). ECAM is described by MCFG; this
        // node gives the OS the bus range, the MMIO window downstream BARs live in, and INTx
        // routing. Bare hex literals only (Trim.py/iasl PCD caveat, see COM0 above).
        //
        Device(PCI0) {
            Name(_HID, EISAID("PNP0A08"))   // PCIe host bridge
            Name(_CID, EISAID("PNP0A03"))   // ...also a legacy PCI host bridge
            Name(_SEG, Zero)
            Name(_BBN, Zero)
            Name(_CCA, One)                 // DMA is cache-coherent (guest RAM is coherent)
            Name(_UID, Zero)

            Name(_CRS, ResourceTemplate() {
                WordBusNumber(
                    ResourceProducer, MinFixed, MaxFixed, PosDecode,
                    0x0000,             // Granularity
                    0x0000,             // Min bus
                    0x0000,             // Max bus (single bus, 1 MB ECAM)
                    0x0000,             // Translation
                    0x0001              // Length (1 bus)
                )
                // MMIO window downstream BAR0 is assigned from (== PcdPciMmio64Base/Size).
                QWordMemory(
                    ResourceProducer, PosDecode, MinFixed, MaxFixed, NonCacheable, ReadWrite,
                    0x0000000000000000, // Granularity
                    0x0000000400000000, // Min (virtual hv_pci BAR window; unused on T8122)
                    0x000000041FFFFFFF, // Max
                    0x0000000000000000, // Translation
                    0x0000000020000000  // Length (512 MB)
                )
            })

            // INTx routing: device 0 INTA -> GSIV 64. A small vSPI that m1n1 injects DIRECTLY
            // into the vGIC (write a Group-1 LR + update_vi, same as the timer PPIs) with level
            // semantics tied to "unread CQ entries" - no AIC software line, so no AIC<->vGIC
            // namespace mixing. Level/ActiveLow is the INTx default for a GSIV _PRT entry.
            Name(_PRT, Package() {
                Package() { 0x0000FFFF, 0, Zero, 64 }   // dev0 INTA -> GSIV 64 (vSPI, direct inject)
            })

            // _OSC: hard NT requirement for a PNP0A08 root. Without it acpi.sys treats the
            // bridge as incomplete and never brings the segment up (MCFG present, ECAM never
            // read). Grant everything the OS asks for (no masking of CDW3).
            Method(_OSC, 4) {
                CreateDWordField(Arg3, 0x00, CDW1)   // status
                CreateDWordField(Arg3, 0x08, CDW3)   // control (left as requested)
                If (Arg0 == ToUUID("33db4d5b-1ff7-401c-9657-7441c03dd766")) {
                    // PCI Host Bridge UUID: grant all - CDW3 unchanged
                } Else {
                    CDW1 |= 0x04                      // unrecognized UUID
                }
                Return (Arg3)
            }

            Method(_STA) { Return(0xF) }
        }

        //
        // PCI Firmware Spec: the ECAM range from MCFG must be claimed as a motherboard
        // resource (PNP0C02) or pci.sys may ignore MCFG entirely - same silent symptom as a
        // missing _OSC. Reserve the 1 MB ECAM window at 0x690000000.
        //
        Device(RES0) {
            Name(_HID, EisaId("PNP0C02"))
            Name(_CRS, ResourceTemplate() {
                QWordMemory(
                    ResourceConsumer, PosDecode, MinFixed, MaxFixed, NonCacheable, ReadWrite,
                    0x0000000000000000, // Granularity
                    0x0000000690000000, // Min - ECAM base (virtual, hv_pci; free on T8122 too)
                    0x00000006900FFFFF, // Max - ECAM base + 1 MB - 1
                    0x0000000000000000, // Translation
                    0x0000000000100000  // Length (1 MB)
                )
            })
            Method(_STA) { Return(0xF) }
        }

        //
        // T8101/T8122 *only* have 1 CPU die, ever, so everything in this node will comprise
        // most of the SoC.
        //
        Device(SOC) {
            Name(_HID, "ACPI0010") // all "processor containers" must have this HID
            Name(_UID, Zero) // unique identifier of the container

            //
            // E-core cluster, typically bootstrap core is here
            //
            Device(CLU0) {
                Name(_HID, "ACPI0010") // all "processor containers" must have this HID
                Name(_UID, 0x1) // unique identifier of the container

                Device(CPU0) {
                    Name(_HID, "ACPI0007")
                    Name(_UID, 0)
                    // Method (_LPI, 0, NotSerialized) {
                    // return(PLPI)
                    // }
                    Method (_STA) {
                        Return (0xF)
                    }
                }

                Device(CPU1) {
                    Name(_HID, "ACPI0007")
                    Name(_UID, 1)
                    // Method (_LPI, 0, NotSerialized) {
                    // return(PLPI)
                    // }
                    Method (_STA) {
                        Return (0xF)
                    }
                }
                Device(CPU2) {
                    Name(_HID, "ACPI0007")
                    Name(_UID, 2)
                    // Method (_LPI, 0, NotSerialized) {
                    // return(PLPI)
                    // }
                    Method (_STA) {
                        Return (0xF)
                    }
                }
                Device(CPU3) {
                    Name(_HID, "ACPI0007")
                    Name(_UID, 3)
                    // Method (_LPI, 0, NotSerialized) {
                    // return(PLPI)
                    // }
                    Method (_STA) {
                        Return (0xF)
                    }
                }
            }

            //
            // P-core cluster.
            //
            Device(CLU1) {
                Name(_HID, "ACPI0010") // all "processor containers" must have this HID
                Name(_UID, 0x2) // unique identifier of the container
                Device(CPU4) {
                    Name(_HID, "ACPI0007")
                    Name(_UID, 4)
                    // Method (_LPI, 0, NotSerialized) {
                    // return(PLPI)
                    // }
                    Method (_STA) {
                        Return (0xF)
                    }
                }

                Device(CPU5) {
                    Name(_HID, "ACPI0007")
                    Name(_UID, 5)
                    // Method (_LPI, 0, NotSerialized) {
                    // return(PLPI)
                    // }
                    Method (_STA) {
                        Return (0xF)
                    }
                }
                Device(CPU6) {
                    Name(_HID, "ACPI0007")
                    Name(_UID, 6)
                    // Method (_LPI, 0, NotSerialized) {
                    // return(PLPI)
                    // }
                    Method (_STA) {
                        Return (0xF)
                    }
                }
                Device(CPU7) {
                    Name(_HID, "ACPI0007")
                    Name(_UID, 7)
                    // Method (_LPI, 0, NotSerialized) {
                    // return(PLPI)
                    // }
                    Method (_STA) {
                        Return (0xF)
                    }
                }
            }
        }
    }
 }
