# SDG Alignment and Application Scope

Project: Latency-Optimal Tactile Reflex System: AI-Assisted Deterministic FPGA-Based Tactile Controller for Robotic Gripper Actuation

Status: academic prototype. It is not a certified safety system or a medical device. The statements below describe *potential contribution* and *application areas*. Any claim must be backed by the project's own measurements.

## 1. Core technical features that drive the alignment

| Feature | Why it matters for the SDG case |
|---|---|
| Fixed-function FPGA hardware transfer function (force to actuator command) | Bounded, repeatable reflex with no software loop in the critical path |
| Independent hardware Safety Governor (max force, sensor fault, E-stop, invalid ADC, safe state) | Protects people, products and equipment even if the AI/ML fails or is wrong |
| AI/ML path is advisory only (contact class, grip condition, excess-force prediction) | Adds adaptability without making safety depend on software |
| Low-cost parts (FSR, SPI ADC, small DC motor, H-bridge, Zynq/Artix board) | Reproducible by universities and small labs |
| Measured, reported latency and jitter (T_FPGA, T_ML, T_physical reported separately) | Evidence-based claims, comparable across labs |

## 2. SDG mapping

Primary goals are 9 and 8. The others are secondary and depend on the application domain.

| SDG | Target (short) | How this project can contribute | Project evidence to collect |
|---|---|---|---|
| **SDG 9** Industry, Innovation and Infrastructure | 9.5 Enhance research and technological capability; 9.b Support domestic technology development | A reproducible FPGA + AI/ML reference design for safety-aware tactile actuation. | Open design files, testbenches, documented method |
| **SDG 8** Decent Work and Economic Growth | 8.2 Productivity through technology upgrading; 8.8 Safe and secure working environments | Hardware-enforced force limits support safer human-robot collaboration and gripping automation. | Safety-response table (force limit enforced when AI says "normal") |
| **SDG 3** Good Health and Well-being | Supports 3.8 access to quality essential health services, as an enabling technology | Basis for safer assistive grippers, prosthetic hands and rehabilitation devices. | Force-limit repeatability, fault-handling tests |
| **SDG 12** Responsible Consumption and Production | 12.3 Reduce food losses along production and supply chains | Gentle, force-limited gripping of fragile goods (produce, food, glassware) reduces damage. | Damage vs. force trials, if you run any |
| **SDG 2** Zero Hunger | 2.3 Agricultural productivity (indirect) | Harvesting and sorting grippers that need delicate, consistent force. | Same as above |
| **SDG 4** Quality Education | 4.4 Relevant technical skills | Low-cost teaching platform for FPGA, embedded AI, functional-safety thinking. | Documentation and lab-ready build guide |
| **SDG 10** Reduced Inequalities | 10.2 Inclusion (indirect) | A low-cost design is a possible route to affordable assistive devices. | Measured bill of materials |

Do not claim the project "achieves" any SDG. The prototype demonstrates an enabling technology.

## 3. National applications (country-neutral; adapt to your country)

| Domain | Use | Feature that matters most |
|---|---|---|
| Domestic manufacturing / SMEs | Force-limited pick-and-place and assembly grippers; cobot end-effectors | Hardware force cap; deterministic response |
| Healthcare and rehabilitation | Prosthetic and assistive grippers; rehab devices | Independent safety layer; low cost |
| Agriculture and food handling | Fruit and vegetable harvesting, sorting, packaging | Gentle grip; contact classification |
| Logistics and warehouses | Handling of mixed, fragile parcels | AI contact/grip state plus hard limit |
| Education and research | FPGA/embedded-AI teaching kit and research testbed | Low cost, open, reproducible |
| Public-sector R&D and startups | Local capability in FPGA-based robotics | Reference design and documentation |

## 4. International applications

| Area | Use |
|---|---|
| Industrial and collaborative robotics | A hardware-enforced force/safety layer concept that can sit beside a higher-level controller. Reference standards for further study: ISO 10218, ISO/TS 15066 (collaborative force/pressure limits), IEC 61508 and ISO 13849 (functional safety). Citing them is not a compliance claim. |
| Humanitarian and low-resource settings | Low-cost assistive grippers and prosthetic-hand research built from commodity parts |
| Hazardous environments | Remote handling where a hardware reflex must still act if the software link drops |
| Space and field robotics research | Fault-tolerant tactile actuation concepts |
| Global education | Open teaching design usable by universities worldwide |
| Research collaboration | Common benchmark: T_FPGA, T_jitter and safety-response tables that other labs can reproduce |

## 5. Limits to state in the report

- A prototype with an FSR is not a calibrated force sensor, so force values are estimates after calibration.
- No standards compliance or medical clearance is claimed.
- AI/ML results come from the dataset actually used and are labelled simulated or real accordingly.
- The deterministic claim covers the FPGA path only. T_ML is reported separately and never added to T_FPGA.
- Application areas are potential uses, not validated deployments.

## 6. Measured results that support the SDG story

Add these to the planned result tables. Fill them in only with real measurements.

| Item | What to record | Supports |
|---|---|---|
| Bill of materials | Actual cost of every part purchased | SDG 9, 10, 4 |
| Safety response | Force at which governor trips, and whether it overrides an AI "normal grip" | SDG 8, 3 |
| T_FPGA and T_jitter | Per the main latency plan | SDG 9 |
| Fragile-object trial (optional) | Object damage with and without the force cap | SDG 12, 2 |
| Reproducibility | Time for a second person to rebuild from the docs | SDG 4, 9 |
