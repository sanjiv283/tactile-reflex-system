# Citation map (review document; not part of paper.md)

"Metadata verified" = authors, title, venue, volume/pages, year and DOI/URL cross-checked against at least two independent records (publisher/repository/library catalogues) via web search.
"Full text reviewed" = someone actually read the paper. **Nobody has, for any item.** Every claim below is therefore limited to what abstracts state.
The author (Sanjiv) must open each DOI and confirm the claim before submission.

| # | Reference | Metadata verified | Full text reviewed | Proposed claim it supports | Not supported by it (do not claim) |
|---|---|---|---|---|---|
| 1 | Dahiya, Metta, Valle, Sandini, "Tactile Sensing—From Humans to Humanoids," IEEE T-RO 26(1):1–20, 2010, doi:10.1109/TRO.2009.2033627 | yes | no | Tactile sensing in robots is an established research area; the survey covers human touch, transduction technologies and tactile arrays. | Any statement about FSRs, ADC sampling rates, latency, force limits. |
| 2 | Romano, Hsiao, Niemeyer, Chitta, Kuchenbecker, "Human-Inspired Robotic Grasp Control with Tactile Sensing," IEEE T-RO 27(6):1067–1079, 2011, doi:10.1109/TRO.2011.2162271 | yes | no | A tactile-based grasp controller can let a parallel-jaw gripper pick up and set down unknown objects gently. | That it uses hysteresis, prediction, FPGA hardware or any particular latency. |
| 3 | Haddadin, Albu-Schäffer, De Luca, Hirzinger, "Collision Detection and Reaction: A Contribution to Safe Physical Human-Robot Interaction," IROS 2008, pp. 3356–3363, doi:10.1109/IROS.2008.4650764 | yes | no | Reaction strategies after detected contact can reduce contact forces (abstract: impact tests with a lightweight robot, reaction methods reduced contact forces). | That the paper treats gripper force limiting or tactile sensors; that any force value is safe. |
| 4 | Haddadin, De Luca, Albu-Schäffer, "Robot Collisions: A Survey on Detection, Isolation, and Identification," IEEE T-RO 33(6):1292–1312, 2017, doi:10.1109/TRO.2017.2723903 | yes | no | Model-based, proprioceptive collision detection/identification is a surveyed area aimed at limiting injury in physical contact. | Anything about tactile or FPGA-based reflexes. |
| 5 | ISO/TS 15066:2016, https://www.iso.org/standard/62996.html | yes (ISO catalogue + national bodies) | no | Technical specification for collaborative industrial robot systems; supplements ISO 10218-1/-2; first edition Feb. 2016, last reviewed 2022. | Any specific force/pressure limit value or compliance of this design. Do not use a number from it until verified from the text. |
| 6 | Analog Devices AD7476A datasheet, https://www.analog.com/en/products/ad7476a.html | product page confirmed; datasheet revision NOT recorded | no | AD7476A is a 12-bit, 1 MSPS SAR ADC with SPI-compatible serial interface. | The 4-leading-zero frame alignment and 20 MHz SCLK limit assumed in `adc_interface.v` (the RTL comment itself says to confirm). |
| 7 | TI DRV8871 datasheet, https://www.ti.com/product/drv8871 | product page confirmed; datasheet revision NOT recorded | no | DRV8871 is a 3.6-A brushed DC motor driver with integrated current regulation. | Any claim about its input-pin behaviour under PWM inhibit (not simulated; no motor tested). |

## Claims that remain unsupported (no citation, no evidence)
1. Any novelty claim (no systematic prior-art search performed).
2. "A hardware reflex path is faster or safer than a software path" (no comparison measured; Wokwi/MCU timing not measured).
3. Hysteresis and latched-fail-safe e-stop as design conventions (no source verified; ISO 13849-1 / IEC 61508 were mentioned in repo docs but not looked up).
4. Slope-based predictive pre-limit as prior art or as improvement (only own simulation evidence).
5. FSR characteristics (the experiments use synthetic ADC codes, not FSR data).
6. Validity limits of simulation-based verification (a reference should be found if this is discussed beyond the author's own limitations).
7. ISO 10218-1:2011: sources conflict on its status (withdrawn 2025-02-05 vs revision in progress); not cited.
8. Collaborative-robot force/pressure limits (needs the ISO/TS 15066 text).
