# Cosmos18_5
MATLAB application for real-time colloidal particle tracking using live camera feedback and dynamic Tango DLL piezo stage control.
# Cosmos 15.8 – Hybrid Particle Tracking & Stage Control App

A GUI-based MATLAB application developed for automated, real-time colloidal particle tracking. The system captures live video streams, processes image frames to calculate physical drift, and dynamically compensates for movement using a motorized micro-positioning stage (*Tango DLL*).

![App Interface](screenshot cosmos.png)

## Key Features

* **Dual Tracking Modes:**
  * **Precision Tracking:** Tracks individual particle trajectories and filters noise/outliers using spatial nearest-neighbor detection.
  * **Center of Mass (CoM) Mode:** Automatically falls back to a weighted Center-of-Mass algorithm when particles aggregate or disappear from the ROI.
* **Hardware Integration:**
  * Live camera preview using MATLAB's Image Acquisition Toolbox.
  * Real-time hardware control of a high-precision stage via C/C++ DLL calls (`Tango_DLL` / `LSX_MoveRel`).
  * Manual stage movement controls (X, Y, Z axes with custom step sizes).
* **Drift & Time Compensation:**
  * Calculates real-time physical drift ($\mu m$).
  * Compensates for execution latency (image processing time) and stage movement acceleration during feedback loops.
* **Data Logging:** Automated output of particle trajectories, frame counts, and mode states into timestamped CSV logs and image folders.

## System Architecture & Setup

### Prerequisites
* **MATLAB** (R2020b or newer recommended)
* **Image Acquisition Toolbox**
* **Image Processing Toolbox**
* Hardware Drivers: `Tango_DLL.dll` placed in the working directory or system PATH.

### Usage
1. Open MATLAB and run `Cosmos15_8`.
2. Click **Connect** to initialize the stage library via serial port (`COM4`).
3. Toggle **Live Preview** to adjust camera focus and framing.
4. Set scale parameters ($\mu m$/px ratio) and click **START** to begin tracking.

## Technical Details

| Parameter | Function |
| :--- | :--- |
| **GUI Framework** | MATLAB `matlab.apps.AppBase` (Object-Oriented) |
| **Image Processing** | Thresholding, binarization, regionprops |
| **Motion Control** | Relational movement via C-Library pointers (`libpointer`) |
| **Output Data** | Saved drift vectors, ROI images, and `.csv` logs |
