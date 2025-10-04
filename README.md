# 🛰️ SHTF-OS — Self-Contained Ham / EmComm Linux Environment

**Version:** 1.0.0-RC1  
**Author:** Aaron Lamb (KV9L)  
**Email:** [aaron@kv9l.com](mailto:aaron@kv9l.com)  
**Website:** [https://kv9l.com](https://kv9l.com)  
**License:** [MIT](LICENSE)

---

## 📖 Overview

**SHTF-OS** is a modular build system that automates deployment of a complete **emergency communications (EmComm)** and **amateur radio** environment for **Linux Mint 22.x XFCE** (Ubuntu 24.04 *Noble Numbat* base).

This project creates a reliable, offline-capable toolkit for radio operators, preppers, and field engineers who require communication when conventional networks fail.

---

## ⚙️ Core Features

| Category | Tools & Components |
|-----------|-------------------|
| **SDR / Scanning** | SDR++, SDRTrunk, GQRX, rtl_433, readsb |
| **Digital Modes** | Fldigi, FLRig, FLMsg, FLAmp, WSJT-X, JS8Call, FreeDV |
| **EmComm / Winlink** | Pat, Direwolf |
| **Signal Decoders** | DSD-FME, OP25, multimon-ng |
| **Satellite / AIS** | Gpredict, SatDump, AIS-Catcher |
| **GPS / Time Sync** | gpsd, chrony |
| **Utilities** | Repeater-START, grig, xdemorse, plus supporting scripts |

---

## 🧩 Modular Layout

Each component is modularized for maintenance and flexibility:

