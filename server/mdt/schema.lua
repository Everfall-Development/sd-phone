---@type table Shared server helpers (server.util): index and constraint bootstrap.
local util       = require 'server.util'
---@type table Column back-fills (server.migrations): applied per table right after its CREATE.
local migrations = require 'server.migrations'

---@type table Schema module; the table returned at end of file. Owns every phone_mdt_* table.
local schema = {}

---@type string[] Every table the MDT owns, in dependency order. server/admin/tables.lua carries
---the same names so `sdphone:wipedata` resets the terminal with the rest of the phone.
schema.tables = {
    'phone_mdt_refs',
    'phone_mdt_profiles',
    'phone_mdt_profile_sessions',
    'phone_mdt_person_records',
    'phone_mdt_vehicles',
    'phone_mdt_offences',
    'phone_mdt_reports',
    'phone_mdt_report_charges',
    'phone_mdt_report_involved',
    'phone_mdt_report_restrictions',
    'phone_mdt_cases',
    'phone_mdt_case_officers',
    'phone_mdt_case_notes',
    'phone_mdt_case_reports',
    'phone_mdt_warrants',
    'phone_mdt_arrests',
    'phone_mdt_enforcement',
    'phone_mdt_bulletins',
    'phone_mdt_audit',
    'phone_mdt_protocols',
    'phone_mdt_medical',
}

---@type table[] The shipped treatment protocols, the medical terminal's counterpart to the penal
---code below. Same INSERT IGNORE contract: a protocol edited in-app survives a restart, a protocol
---added in a later release still lands. code, label, category, priority, description, body.
local PROTOCOLS = {
    { 'TP 101', 'Primary Survey', 'assessment', 'immediate', 'Airway, breathing, circulation, disability, exposure, in that order.',
      'Establish scene safety before approach. Check responsiveness, then airway patency with cervical spine control where trauma is suspected. Assess breathing rate and effort, then circulation by central and peripheral pulse. Record a baseline set of observations before any intervention that is not immediately life saving.' },
    { 'TP 102', 'Catastrophic Haemorrhage', 'trauma', 'immediate', 'Control life threatening bleeding before anything else.',
      'Direct pressure first. Escalate to a pressure dressing, then to a tourniquet placed high and tight on the affected limb. Record the time the tourniquet went on and hand that time over verbally; it decides what the receiving team can still save.' },
    { 'TP 103', 'Airway Obstruction', 'airway', 'immediate', 'Clear and maintain a patent airway.',
      'Encourage coughing while the patient can. On a failing cough, alternate five back blows with five abdominal thrusts. On unresponsiveness, begin chest compressions and inspect the airway on each ventilation attempt.' },
    { 'TP 104', 'Cardiac Arrest', 'cardiac', 'immediate', 'Compressions, early defibrillation, minimal interruption.',
      'Begin compressions at 100 to 120 per minute to a depth of 5 to 6cm. Apply the defibrillator as soon as it is to hand and follow its rhythm analysis. Rotate the compressor every two minutes. Do not stop to move the patient until there is return of circulation or the resuscitation is called.' },
    { 'TP 105', 'Chest Pain', 'cardiac', 'urgent', 'Treat as cardiac until it is ruled out.',
      'Sit the patient upright and keep them still. Record observations at first contact and every five minutes. Any pain radiating to jaw or left arm, or accompanied by sweating, nausea or breathlessness, travels as an emergency regardless of how well the patient looks.' },
    { 'TP 106', 'Anaphylaxis', 'medical', 'immediate', 'Adrenaline first, and early.',
      'Remove the trigger where it can be removed. Give adrenaline into the outer thigh without waiting for the airway to close. Lay the patient flat with legs raised unless breathing is compromised, in which case sit them up. Repeat after five minutes if there is no improvement.' },
    { 'TP 107', 'Opioid Overdose', 'medical', 'immediate', 'Support ventilation, then reverse.',
      'Respiratory failure is what kills, so ventilate before anything else. Give naloxone once ventilation is supported and titrate to breathing rather than to consciousness. Expect the reversal to wear off before the opioid does, and never leave the patient unattended after it.' },
    { 'TP 108', 'Major Haemorrhage', 'trauma', 'immediate', 'Stop the bleeding, keep them warm, move early.',
      'Pressure and packing for compressible sites, pelvic binder for a suspected pelvic fracture, splint for long bone fractures. Keep the patient warm; a cold patient stops clotting. This is a load and go, not a stay and play.' },
    { 'TP 109', 'Spinal Immobilisation', 'trauma', 'urgent', 'Immobilise on mechanism, not on symptoms.',
      'Manual in line stabilisation from first contact. Apply a collar sized to the patient and move with a scoop or long board. A patient who is walking on arrival may still have an unstable spine; the mechanism of injury decides this, not how they present.' },
    { 'TP 110', 'Burns', 'trauma', 'urgent', 'Cool the burn, warm the patient.',
      'Irrigate with cool running water for twenty minutes and no longer. Remove jewellery and constricting clothing early, before swelling sets in. Cover with a clean non adherent dressing. Estimate the surface area involved and pass that figure on; it decides the receiving unit.' },
    { 'TP 111', 'Seizure', 'medical', 'urgent', 'Protect from harm, time it, do not restrain.',
      'Clear the space around the patient and cushion the head. Time the seizure from first movement. Never place anything in the mouth. A seizure past five minutes, or a second seizure without recovery in between, is an emergency in its own right.' },
    { 'TP 112', 'Hypoglycaemia', 'medical', 'urgent', 'Sugar by the safest available route.',
      'Oral glucose for a patient who can protect their own airway. For a patient who cannot, use the parenteral route. Re-test after ten minutes and feed a longer acting carbohydrate once the patient is alert, or they will simply drop again.' },
    { 'TP 113', 'Drowning', 'medical', 'immediate', 'Ventilate first; this arrest is hypoxic.',
      'Give five rescue breaths before compressions, because the cause is oxygen and not rhythm. Assume spinal injury on any dive or fall. Remove wet clothing and insulate the patient early; hypothermia follows immersion faster than it is expected to.' },
    { 'TP 114', 'Obstetric Emergency', 'medical', 'immediate', 'Two patients, one of whom cannot be assessed.',
      'Position the mother on her left side to take the weight off the vena cava. If delivery is imminent, prepare for it where you stand rather than moving. Keep the newborn warm and dry and record the time of birth. Any bleeding in pregnancy travels as an emergency.' },
    { 'TP 115', 'Psychiatric Crisis', 'medical', 'routine', 'Scene safety, then rapport, then assessment.',
      'Do not enter alone where there is a weapon or a threat of one. Keep an exit behind you. Speak plainly and do not argue with a delusion. Rule out the physical causes that mimic a crisis, low blood sugar and hypoxia among them, before recording it as psychiatric.' },
    { 'TP 116', 'Death on Scene', 'admin', 'routine', 'Recognition of life extinct and what follows it.',
      'Resuscitation is not begun where injuries are incompatible with life or where rigor is established. Record the time of recognition, disturb the scene as little as possible, and hand the location over to police. The report for this carries the Death type.' },
    { 'TP 117', 'Refusal of Treatment', 'admin', 'routine', 'A competent adult may refuse, and that refusal is recorded.',
      'Establish that the patient has capacity for this decision at this time. Explain the risks in plain language and record that you did. Advise them to call again if anything changes. Document the refusal in a Patient Care report; the report is the protection for both sides.' },
    { 'TP 118', 'Handover', 'admin', 'routine', 'The structured handover the receiving team expects.',
      'Age and presenting complaint, mechanism or history, the observations recorded and the trend across them, treatment given and the response to it, and anything outstanding. Deliver it once, to the person taking over, and file the report before going back on the road.' },
}

---@type table[] The shipped penal code. Seeded with INSERT IGNORE so a code edited in-app through
---offences.manage survives a restart while a code added in a later release still lands.
local OFFENCES = {
    { 'PC 101', 'Simple Assault', 'misdemeanor', 6, 500, 'Unwanted physical contact with another person that causes no lasting injury.' },
    { 'PC 102', 'Assault', 'misdemeanor', 12, 900, 'Deliberately causing injury to another person without using a weapon.' },
    { 'PC 103', 'Aggravated Assault', 'felony', 24, 1500, 'Recklessly causing serious bodily injury in the course of a confrontation.' },
    { 'PC 104', 'Assault With a Deadly Weapon', 'felony', 32, 4000, 'Causing or attempting to cause injury while using or displaying a weapon.' },
    { 'PC 105', 'Assault on a Peace Officer', 'felony', 40, 5000, 'Assaulting a law enforcement officer who is on duty.' },
    { 'PC 106', 'Assault on a Medical Responder', 'felony', 36, 4500, 'Assaulting a paramedic or fire responder who is on duty.' },
    { 'PC 107', 'Criminal Threats', 'misdemeanor', 8, 600, 'Stating an intent to cause harm to a person or to their property.' },
    { 'PC 108', 'Reckless Endangerment', 'misdemeanor', 12, 1000, 'Acting with disregard for safety in a way that puts another at risk of serious injury.' },
    { 'PC 109', 'Torture', 'felony', 45, 6000, 'Inflicting prolonged physical or mental suffering on a restrained person.' },
    { 'PC 110', 'Involuntary Manslaughter', 'felony', 60, 8000, 'Causing the death of another person through recklessness rather than intent.' },
    { 'PC 111', 'Vehicular Manslaughter', 'felony', 70, 8000, 'Causing the death of another person while operating a vehicle recklessly.' },
    { 'PC 112', 'Attempted Murder', 'felony', 55, 9000, 'Attacking another person with a clear intent to kill them.' },
    { 'PC 113', 'Second Degree Murder', 'felony', 95, 15000, 'An intentional killing carried out without planning.' },
    { 'PC 114', 'First Degree Murder', 'felony', 110, 18000, 'A killing that is willful, deliberate and planned in advance.' },
    { 'PC 115', 'Murder of a Peace Officer', 'felony', 130, 25000, 'Killing a law enforcement officer who is on duty.' },
    { 'PC 116', 'Attempted Murder of a Peace Officer', 'felony', 70, 12000, 'Attacking an on-duty officer with a clear intent to kill them.' },
    { 'PC 117', 'Accessory to Murder', 'felony', 55, 8000, 'Assisting, sheltering or acting alongside the person who carried out a killing.' },
    { 'PC 118', 'Unlawful Imprisonment', 'misdemeanor', 10, 700, 'Holding a person against their will without lawful authority.' },
    { 'PC 119', 'Kidnapping', 'felony', 20, 1500, 'Taking a person and moving them against their will.' },
    { 'PC 120', 'Attempted Kidnapping', 'felony', 12, 900, 'Trying and failing to take a person against their will.' },
    { 'PC 121', 'Accessory to Kidnapping', 'felony', 10, 800, 'Assisting in the taking of a person against their will.' },
    { 'PC 122', 'Hostage Taking', 'felony', 26, 2000, 'Holding a person against their will to force a payment or an outcome.' },
    { 'PC 123', 'Gang Related Shooting', 'felony', 35, 3000, 'Discharging a firearm in the course of organised criminal activity.' },
    { 'PC 124', 'Stalking', 'felony', 30, 1800, 'Repeatedly following or monitoring a person without their consent.' },
    { 'PC 125', 'Harassment', 'misdemeanor', 10, 600, 'Repeated unwanted contact or verbal abuse directed at a person.' },
    { 'PC 126', 'Desecration of Human Remains', 'felony', 22, 2000, 'Disturbing, moving or damaging the remains of a deceased person.' },
    { 'PC 127', 'Cannibalism', 'felony', 100, 20000, 'Consuming the flesh of another person.' },

    { 'PC 201', 'Petty Theft', 'infraction', 0, 250, 'Taking property of minor value.' },
    { 'PC 202', 'Grand Theft', 'misdemeanor', 10, 800, 'Taking property of substantial value.' },
    { 'PC 203', 'Grand Larceny', 'felony', 40, 6000, 'Taking property of very high value.' },
    { 'PC 204', 'Vehicle Theft', 'felony', 15, 1200, 'Taking a vehicle belonging to another person without their permission.' },
    { 'PC 205', 'Armed Vehicle Theft', 'felony', 32, 3500, 'Taking a vehicle without permission while carrying a weapon.' },
    { 'PC 206', 'Carjacking', 'felony', 30, 2500, 'Forcing an occupant out of their vehicle in order to take it.' },
    { 'PC 207', 'Theft of an Aircraft', 'felony', 24, 2000, 'Taking an aircraft without the owner permission.' },
    { 'PC 208', 'Theft of a Vessel', 'felony', 20, 1500, 'Taking a boat or watercraft without the owner permission.' },
    { 'PC 209', 'Burglary', 'misdemeanor', 12, 700, 'Entering a building unlawfully intending to commit a crime inside it.' },
    { 'PC 210', 'Robbery', 'felony', 25, 2000, 'Taking property from a person or place by force or the threat of force.' },
    { 'PC 211', 'Armed Robbery', 'felony', 32, 3500, 'Taking property by force while carrying or displaying a weapon.' },
    { 'PC 212', 'Attempted Robbery', 'felony', 18, 1200, 'Trying and failing to take property by force.' },
    { 'PC 213', 'Accessory to Robbery', 'felony', 14, 1200, 'Assisting in a robbery without carrying it out.' },
    { 'PC 214', 'Leaving Without Paying', 'infraction', 0, 400, 'Leaving a business without paying for goods or services received.' },
    { 'PC 215', 'Possession of Stolen Property', 'misdemeanor', 10, 600, 'Holding property known or reasonably believed to be stolen.' },
    { 'PC 216', 'Possession of Government Property', 'felony', 18, 1500, 'Holding equipment issued only to government employees.' },
    { 'PC 217', 'Possession of Burglary Tools', 'misdemeanor', 10, 600, 'Carrying equipment intended for forced entry or theft.' },
    { 'PC 218', 'Sale of Stolen Property', 'felony', 18, 1500, 'Selling or trading property known to be stolen.' },
    { 'PC 219', 'Possession of Marked Currency', 'misdemeanor', 12, 900, 'Holding cash known to be the proceeds of a crime.' },
    { 'PC 220', 'Looting', 'felony', 20, 1800, 'Taking property from the scene of an emergency, disaster or public disorder.' },

    { 'PC 301', 'Fraud', 'misdemeanor', 10, 700, 'Deceiving another person for financial gain.' },
    { 'PC 302', 'Forgery', 'misdemeanor', 14, 900, 'Producing or altering a document in order to pass it off as genuine.' },
    { 'PC 303', 'Identity Theft', 'felony', 20, 2000, 'Using the identity of another person without their consent.' },
    { 'PC 304', 'Possession of Stolen Identification', 'misdemeanor', 10, 700, 'Holding identification documents belonging to another person.' },
    { 'PC 305', 'Possession of Government Identification', 'misdemeanor', 18, 1800, 'Holding identification issued to a government employee.' },
    { 'PC 306', 'Impersonating Another Person', 'misdemeanor', 14, 1200, 'Falsely presenting yourself as another named individual.' },
    { 'PC 307', 'Impersonating a Peace Officer', 'felony', 26, 3000, 'Falsely presenting yourself as a law enforcement officer.' },
    { 'PC 308', 'Impersonating a Medical Professional', 'felony', 24, 2500, 'Falsely presenting yourself as a doctor or paramedic.' },
    { 'PC 309', 'Impersonating a Judge', 'felony', 32, 4000, 'Falsely presenting yourself as a member of the judiciary.' },
    { 'PC 310', 'Extortion', 'felony', 22, 1500, 'Demanding money or property under threat of harm or exposure.' },
    { 'PC 311', 'Money Laundering', 'felony', 40, 8000, 'Passing criminal proceeds through legitimate accounts to disguise their origin.' },
    { 'PC 312', 'Embezzlement', 'felony', 45, 10000, 'Diverting funds held in trust into personal accounts.' },
    { 'PC 313', 'Insurance Fraud', 'felony', 20, 2500, 'Making a knowingly false claim against an insurer.' },
    { 'PC 314', 'Tax Evasion', 'felony', 24, 5000, 'Deliberately concealing income or assets from the city.' },
    { 'PC 315', 'Counterfeiting', 'felony', 35, 6000, 'Producing imitation currency or official documents.' },

    { 'PC 401', 'Littering', 'infraction', 0, 200, 'Discarding refuse outside a designated bin.' },
    { 'PC 402', 'Vandalism', 'infraction', 0, 350, 'Deliberately damaging or defacing property.' },
    { 'PC 403', 'Vandalism of Government Property', 'misdemeanor', 15, 1200, 'Deliberately damaging property belonging to the city.' },
    { 'PC 404', 'Criminal Damage', 'misdemeanor', 12, 900, 'Destroying property belonging to another person.' },
    { 'PC 405', 'Arson', 'felony', 20, 2500, 'Deliberately setting fire to property.' },
    { 'PC 406', 'Aggravated Arson', 'felony', 45, 8000, 'Setting fire to a property while people are inside it.' },
    { 'PC 407', 'Trespassing', 'misdemeanor', 8, 400, 'Remaining on property where you have no lawful right to be.' },
    { 'PC 408', 'Felony Trespassing', 'felony', 15, 1500, 'Repeatedly entering property after being formally excluded from it.' },
    { 'PC 409', 'Tampering With a Vehicle', 'misdemeanor', 12, 800, 'Interfering with the normal function of another person vehicle.' },
    { 'PC 410', 'Tampering With Utilities', 'felony', 18, 2000, 'Interfering with power, water or communications infrastructure.' },

    { 'PC 501', 'Resisting Arrest', 'misdemeanor', 6, 400, 'Physically refusing to submit to a lawful arrest.' },
    { 'PC 502', 'Evading on Foot', 'misdemeanor', 8, 500, 'Fleeing from officers attempting a lawful detention.' },
    { 'PC 503', 'Obstruction of Justice', 'misdemeanor', 10, 600, 'Acting in a way that hinders a lawful investigation.' },
    { 'PC 504', 'Felony Obstruction of Justice', 'felony', 16, 1200, 'Hindering a lawful investigation by force or by threat.' },
    { 'PC 505', 'Evidence Tampering', 'felony', 20, 1500, 'Destroying, hiding or altering evidence in an investigation.' },
    { 'PC 506', 'Witness Tampering', 'felony', 26, 3000, 'Coaching, bribing or intimidating a witness.' },
    { 'PC 507', 'False Reporting', 'misdemeanor', 10, 800, 'Reporting a crime or an emergency that did not take place.' },
    { 'PC 508', 'Misuse of Emergency Services', 'infraction', 0, 600, 'Using an emergency line or service for a non-emergency.' },
    { 'PC 509', 'Perjury', 'felony', 22, 2500, 'Making a false statement while under oath.' },
    { 'PC 510', 'Contempt of Court', 'misdemeanor', 12, 1500, 'Disrupting or defying the authority of a court in session.' },
    { 'PC 511', 'Failure to Appear', 'misdemeanor', 15, 1500, 'Failing to attend a court hearing you were ordered to attend.' },
    { 'PC 512', 'Violating a Court Order', 'misdemeanor', 12, 1200, 'Breaching a condition imposed by a court.' },
    { 'PC 513', 'Violating a Restraining Order', 'felony', 20, 2500, 'Approaching a person a court has ordered you to stay away from.' },
    { 'PC 514', 'Escape From Custody', 'felony', 14, 1000, 'Leaving lawful custody without authorisation.' },
    { 'PC 515', 'Escape From a Correctional Facility', 'felony', 32, 3000, 'Leaving a state or county detention facility without release.' },
    { 'PC 516', 'Aiding an Escape', 'felony', 28, 2500, 'Assisting a person to leave lawful custody.' },
    { 'PC 517', 'Attempted Jailbreak', 'felony', 22, 2000, 'Attempting to remove a person from a detention facility.' },
    { 'PC 518', 'Bribery of a Public Official', 'felony', 24, 4000, 'Offering money or favours to influence an official act.' },
    { 'PC 519', 'Public Corruption', 'felony', 55, 12000, 'Using a public office for personal gain.' },
    { 'PC 520', 'Harbouring a Fugitive', 'misdemeanor', 12, 1200, 'Sheltering a person known to be wanted.' },
    { 'PC 521', 'Aiding and Abetting', 'misdemeanor', 15, 700, 'Assisting or encouraging another person to commit a crime.' },
    { 'PC 522', 'Conspiracy', 'misdemeanor', 12, 700, 'Agreeing with another person to commit a crime.' },
    { 'PC 523', 'Disobeying a Lawful Order', 'infraction', 0, 700, 'Refusing to comply with a lawful instruction from an officer.' },
    { 'PC 524', 'Failure to Provide Identification', 'misdemeanor', 12, 1000, 'Refusing to identify yourself when lawfully required to do so.' },
    { 'PC 525', 'Contraband in a Government Facility', 'felony', 24, 1500, 'Carrying prohibited items inside a government building.' },
    { 'PC 526', 'Unlawful Practice of a Profession', 'felony', 16, 1500, 'Providing a licensed service without holding the licence.' },
    { 'PC 527', 'Vigilantism', 'felony', 28, 1800, 'Enforcing the law without any legal authority to do so.' },

    { 'PC 601', 'Disorderly Conduct', 'infraction', 0, 250, 'Behaving in a way that creates a hazardous or offensive condition in public.' },
    { 'PC 602', 'Disturbing the Peace', 'infraction', 0, 350, 'Behaving in a way that disrupts public order or the quiet of a neighbourhood.' },
    { 'PC 603', 'Public Intoxication', 'infraction', 0, 400, 'Being intoxicated in public to the point of being a risk to yourself or others.' },
    { 'PC 604', 'Public Indecency', 'misdemeanor', 8, 700, 'Exposing yourself in a public place.' },
    { 'PC 605', 'Loitering', 'infraction', 0, 200, 'Remaining without purpose in a place after being asked to move on.' },
    { 'PC 606', 'Loitering on Government Property', 'infraction', 0, 500, 'Remaining without business inside or around a government facility.' },
    { 'PC 607', 'Unlawful Assembly', 'misdemeanor', 10, 800, 'Gathering in numbers at a location that requires prior approval.' },
    { 'PC 608', 'Inciting a Riot', 'felony', 26, 2500, 'Urging a crowd toward violence or destruction.' },
    { 'PC 609', 'Rioting', 'felony', 20, 1800, 'Taking part in a violent public disturbance.' },
    { 'PC 610', 'Anti-Mask Violation', 'infraction', 0, 700, 'Concealing your face inside a restricted zone.' },
    { 'PC 611', 'Solicitation', 'misdemeanor', 8, 500, 'Offering or arranging an unlawful service in a public place.' },
    { 'PC 612', 'Illegal Gambling', 'misdemeanor', 12, 1200, 'Operating or taking part in an unlicensed game of chance.' },
    { 'PC 613', 'Operating an Unlicensed Business', 'misdemeanor', 10, 1000, 'Trading without the licence the city requires.' },
    { 'PC 614', 'Noise Violation', 'infraction', 0, 250, 'Producing sound above the level permitted for the area and the hour.' },

    { 'PC 701', 'Possession of Marijuana', 'misdemeanor', 5, 300, 'Holding a small quantity of marijuana for personal use.' },
    { 'PC 702', 'Cultivation of Marijuana', 'misdemeanor', 10, 800, 'Growing marijuana plants without a licence.' },
    { 'PC 703', 'Commercial Cultivation of Marijuana', 'felony', 26, 2000, 'Growing marijuana plants at a scale intended for supply.' },
    { 'PC 704', 'Manufacture of Marijuana Products', 'felony', 18, 1200, 'Processing marijuana into a saleable product.' },
    { 'PC 705', 'Possession of Marijuana for Supply', 'felony', 28, 3000, 'Holding marijuana in a quantity indicating an intent to supply.' },
    { 'PC 706', 'Possession of Cocaine', 'misdemeanor', 7, 500, 'Holding a small quantity of cocaine for personal use.' },
    { 'PC 707', 'Manufacture of Cocaine', 'felony', 26, 1800, 'Processing coca product into a saleable form.' },
    { 'PC 708', 'Possession of Cocaine for Supply', 'felony', 34, 4500, 'Holding cocaine in a quantity indicating an intent to supply.' },
    { 'PC 709', 'Possession of Methamphetamine', 'misdemeanor', 7, 500, 'Holding a small quantity of methamphetamine for personal use.' },
    { 'PC 710', 'Manufacture of Methamphetamine', 'felony', 28, 2000, 'Producing methamphetamine from precursor chemicals.' },
    { 'PC 711', 'Possession of Methamphetamine for Supply', 'felony', 34, 4500, 'Holding methamphetamine in a quantity indicating an intent to supply.' },
    { 'PC 712', 'Possession of Heroin', 'misdemeanor', 8, 600, 'Holding a small quantity of heroin for personal use.' },
    { 'PC 713', 'Manufacture of Heroin', 'felony', 30, 2200, 'Processing opiate product into a saleable form.' },
    { 'PC 714', 'Possession of Heroin for Supply', 'felony', 36, 5000, 'Holding heroin in a quantity indicating an intent to supply.' },
    { 'PC 715', 'Possession of Ecstasy', 'misdemeanor', 7, 500, 'Holding a small quantity of ecstasy for personal use.' },
    { 'PC 716', 'Manufacture of Ecstasy', 'felony', 26, 1800, 'Producing ecstasy tablets from precursor chemicals.' },
    { 'PC 717', 'Possession of Ecstasy for Supply', 'felony', 34, 4500, 'Holding ecstasy in a quantity indicating an intent to supply.' },
    { 'PC 718', 'Possession of Prescription Medication', 'misdemeanor', 6, 400, 'Holding prescription medication issued to somebody else.' },
    { 'PC 719', 'Manufacture of Prescription Medication', 'felony', 26, 1800, 'Producing prescription medication outside a licensed pharmacy.' },
    { 'PC 720', 'Possession of Prescription Medication for Supply', 'felony', 32, 4000, 'Holding prescription medication in a quantity indicating an intent to supply.' },
    { 'PC 721', 'Possession of Psilocybin', 'misdemeanor', 6, 400, 'Holding a small quantity of psilocybin for personal use.' },
    { 'PC 722', 'Possession of Psilocybin for Supply', 'felony', 30, 3500, 'Holding psilocybin in a quantity indicating an intent to supply.' },
    { 'PC 723', 'Sale of a Controlled Substance', 'misdemeanor', 12, 1200, 'Selling a controlled substance in a personal quantity.' },
    { 'PC 724', 'Drug Trafficking', 'felony', 48, 9000, 'Moving controlled substances in bulk.' },
    { 'PC 725', 'Operating a Drug Laboratory', 'felony', 40, 7000, 'Running a site set up for the manufacture of controlled substances.' },
    { 'PC 726', 'Distribution to a Minor', 'felony', 45, 8000, 'Supplying a controlled substance to a person under age.' },
    { 'PC 727', 'Possession of Drug Paraphernalia', 'infraction', 0, 250, 'Holding equipment intended for the use of a controlled substance.' },

    { 'PC 801', 'Possession of a Class A Firearm', 'felony', 10, 600, 'Holding a small calibre handgun without a licence.' },
    { 'PC 802', 'Possession of a Class B Firearm', 'felony', 16, 1200, 'Holding a large calibre handgun without a licence.' },
    { 'PC 803', 'Possession of a Class C Firearm', 'felony', 30, 4000, 'Holding an automatic or military grade firearm without a licence.' },
    { 'PC 804', 'Possession of a Class D Firearm', 'felony', 24, 2000, 'Holding a shotgun or rifle without a licence.' },
    { 'PC 805', 'Sale of a Class A Firearm', 'felony', 16, 1200, 'Selling a small calibre handgun without a dealer licence.' },
    { 'PC 806', 'Sale of a Class B Firearm', 'felony', 22, 2200, 'Selling a large calibre handgun without a dealer licence.' },
    { 'PC 807', 'Sale of a Class C Firearm', 'felony', 36, 7000, 'Selling an automatic or military grade firearm without a dealer licence.' },
    { 'PC 808', 'Sale of a Class D Firearm', 'felony', 30, 3500, 'Selling a shotgun or rifle without a dealer licence.' },
    { 'PC 809', 'Weapon Trafficking', 'felony', 50, 10000, 'Moving firearms in bulk for supply.' },
    { 'PC 810', 'Possession of a Defaced Firearm', 'felony', 20, 1800, 'Holding a firearm whose serial number has been removed or altered.' },
    { 'PC 811', 'Possession of Illegal Firearm Modifications', 'misdemeanor', 10, 400, 'Holding attachments that are unlawful to fit to a firearm.' },
    { 'PC 812', 'Brandishing a Weapon', 'misdemeanor', 14, 600, 'Deliberately displaying a weapon in order to intimidate.' },
    { 'PC 813', 'Criminal Use of a Weapon', 'misdemeanor', 12, 700, 'Using a weapon in the course of committing another offence.' },
    { 'PC 814', 'Discharging a Firearm in Public', 'misdemeanor', 15, 1200, 'Firing a weapon in a public place without lawful cause.' },
    { 'PC 815', 'Possession of Explosives', 'felony', 28, 3000, 'Holding explosive material without a licence.' },
    { 'PC 816', 'Criminal Use of Explosives', 'felony', 35, 4000, 'Using explosives in the course of committing another offence.' },
    { 'PC 817', 'Possession of a Prohibited Weapon', 'felony', 26, 2500, 'Holding a weapon that may not be owned under any licence.' },
    { 'PC 818', 'Insurrection', 'felony', 120, 25000, 'Taking up arms against the government of the city.' },

    { 'PC 901', 'Third Degree Speeding', 'infraction', 0, 200, 'Exceeding the posted limit by up to fifteen miles per hour.' },
    { 'PC 902', 'Second Degree Speeding', 'infraction', 0, 400, 'Exceeding the posted limit by up to thirty five miles per hour.' },
    { 'PC 903', 'First Degree Speeding', 'infraction', 0, 750, 'Exceeding the posted limit by more than thirty five miles per hour.' },
    { 'PC 904', 'Failure to Stop', 'infraction', 0, 500, 'Failing to stop at a sign, a signal or a lawful direction.' },
    { 'PC 905', 'Failure to Obey a Traffic Device', 'infraction', 0, 150, 'Ignoring a signal, a sign or a road marking.' },
    { 'PC 906', 'Failure to Maintain Lane', 'infraction', 0, 250, 'Drifting out of the marked lane.' },
    { 'PC 907', 'Illegal Turn', 'infraction', 0, 150, 'Turning where the movement is prohibited.' },
    { 'PC 908', 'Illegal U-Turn', 'infraction', 0, 150, 'Reversing direction where the movement is prohibited.' },
    { 'PC 909', 'Illegal Passing', 'infraction', 0, 300, 'Overtaking in a manner or a place that is prohibited.' },
    { 'PC 910', 'Failure to Yield', 'infraction', 0, 300, 'Failing to give way where the road requires it.' },
    { 'PC 911', 'Failure to Yield to an Emergency Vehicle', 'infraction', 0, 600, 'Failing to give way to a responding emergency vehicle.' },
    { 'PC 912', 'Unsafe Lane Change', 'infraction', 0, 250, 'Changing lanes without leaving safe space for other traffic.' },
    { 'PC 913', 'Driving Without Headlights', 'infraction', 0, 250, 'Operating a vehicle after dark without working lights.' },
    { 'PC 914', 'Failure to Signal', 'infraction', 0, 150, 'Turning or changing lanes without signalling the movement.' },
    { 'PC 915', 'Unauthorised Parking', 'infraction', 0, 300, 'Leaving a vehicle where parking is not permitted.' },
    { 'PC 916', 'Abandoned Vehicle', 'infraction', 0, 250, 'Leaving a non-functional vehicle on the roadway.' },
    { 'PC 917', 'Negligent Driving', 'infraction', 0, 350, 'Driving without proper attention to the road.' },
    { 'PC 918', 'Reckless Driving', 'misdemeanor', 10, 800, 'Driving with deliberate disregard for the safety of others.' },
    { 'PC 919', 'Street Racing', 'felony', 15, 1800, 'Taking part in a speed contest on a public road.' },
    { 'PC 920', 'Driving Under the Influence', 'misdemeanor', 8, 900, 'Operating a vehicle while impaired.' },
    { 'PC 921', 'Driving Under the Influence Causing Injury', 'felony', 30, 4000, 'Injuring another person while driving impaired.' },
    { 'PC 922', 'Hit and Run', 'misdemeanor', 12, 900, 'Leaving the scene after striking a person, a vehicle or property.' },
    { 'PC 923', 'Hit and Run Causing Injury', 'felony', 25, 3000, 'Leaving the scene of a collision in which somebody was injured.' },
    { 'PC 924', 'Evading in a Vehicle', 'misdemeanor', 10, 800, 'Failing to stop for a marked police vehicle.' },
    { 'PC 925', 'Reckless Evading', 'felony', 18, 1800, 'Fleeing police in a vehicle with disregard for public safety.' },
    { 'PC 926', 'Driving Without a Licence', 'infraction', 0, 500, 'Operating a vehicle without holding a valid licence.' },
    { 'PC 927', 'Driving While Suspended', 'misdemeanor', 10, 1000, 'Operating a vehicle while your licence is suspended.' },
    { 'PC 928', 'Operating an Unregistered Vehicle', 'infraction', 0, 350, 'Operating a vehicle whose registration has lapsed.' },
    { 'PC 929', 'Jaywalking', 'infraction', 0, 150, 'Crossing a roadway outside a marked crossing.' },
    { 'PC 930', 'Unlawful Use of a Motor Vehicle', 'misdemeanor', 10, 800, 'Using a vehicle for a purpose the owner did not permit.' },
    { 'PC 931', 'Piloting Without a Licence', 'felony', 20, 1800, 'Operating an aircraft without holding a pilot licence.' },
    { 'PC 932', 'Flying Into Restricted Airspace', 'felony', 22, 2000, 'Entering controlled airspace without clearance.' },
    { 'PC 933', 'Operating a Vessel Without a Licence', 'infraction', 0, 500, 'Operating a boat without holding a valid licence.' },

    { 'PC 1001', 'Hunting Without a Licence', 'infraction', 0, 450, 'Taking game without holding a hunting licence.' },
    { 'PC 1002', 'Hunting in a Restricted Area', 'infraction', 0, 500, 'Taking game in an area that is closed to hunting.' },
    { 'PC 1003', 'Hunting Outside Permitted Hours', 'infraction', 0, 450, 'Taking game outside the hours set for the season.' },
    { 'PC 1004', 'Hunting With a Prohibited Weapon', 'misdemeanor', 10, 800, 'Taking game with a weapon not approved for hunting.' },
    { 'PC 1005', 'Exceeding the Bag Limit', 'misdemeanor', 10, 1000, 'Taking more game than the season allows.' },
    { 'PC 1006', 'Poaching', 'felony', 20, 1500, 'Taking a protected species.' },
    { 'PC 1007', 'Animal Cruelty', 'misdemeanor', 12, 800, 'Causing unnecessary suffering to an animal.' },
    { 'PC 1008', 'Illegal Dumping', 'misdemeanor', 12, 1500, 'Discharging waste outside a licensed facility.' },
    { 'PC 1009', 'Environmental Contamination', 'felony', 26, 6000, 'Releasing hazardous material into the land, the air or the water.' },
}

---@type integer Offence rows written per INSERT, so the seed never builds one enormous statement.
local SEED_CHUNK = 40

---Seeds the penal code. INSERT IGNORE rather than an upsert: a code an admin has retuned through
---offences.manage must survive a restart, while a code added in a later release still lands.
local function seedOffences()
    local i = 1
    while i <= #OFFENCES do
        local marks, args = {}, {}
        local last = math.min(i + SEED_CHUNK - 1, #OFFENCES)
        for n = i, last do
            local row = OFFENCES[n]
            marks[#marks + 1] = '(?, ?, ?, ?, ?, ?)'
            args[#args + 1] = row[1]
            args[#args + 1] = row[2]
            args[#args + 1] = row[3]
            args[#args + 1] = row[4]
            args[#args + 1] = row[5]
            args[#args + 1] = row[6]
        end
        MySQL.query.await(
            'INSERT IGNORE INTO phone_mdt_offences (`code`, `label`, `class`, `months`, `fine`, `description`) VALUES '
                .. table.concat(marks, ', '),
            args)
        i = last + 1
    end
end

---Creates every MDT table and seeds the penal code. Run once at boot, in dependency order so the
---foreign keys below always find their parent.
function schema.ensureSchema()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS phone_mdt_refs (
            `kind`    VARCHAR(16)  NOT NULL,
            `counter` INT UNSIGNED NOT NULL DEFAULT 0,
            PRIMARY KEY (`kind`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
    ]])
    migrations.apply('phone_mdt_refs')

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS phone_mdt_profiles (
            `citizenid`   VARCHAR(64)  NOT NULL,
            `fullname`    VARCHAR(96)  NOT NULL,
            `callsign`    VARCHAR(16)  NULL,
            `badge`       VARCHAR(16)  NULL,
            `radio`       VARCHAR(16)  NULL,
            `department`  VARCHAR(64)  NOT NULL DEFAULT '',
            `rank_label`  VARCHAR(64)  NOT NULL DEFAULT '',
            `grade_level` INT          NOT NULL DEFAULT 0,
            `avatar`      VARCHAR(512) NULL,
            `notes`       TEXT         NULL,
            `created_at`  INT          NOT NULL,
            `updated_at`  INT          NOT NULL,
            PRIMARY KEY (`citizenid`),
            UNIQUE KEY uniq_callsign (`callsign`),
            KEY idx_department (`department`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
    ]])
    migrations.apply('phone_mdt_profiles')

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS phone_mdt_profile_sessions (
            `id`        INT         NOT NULL AUTO_INCREMENT,
            `citizenid` VARCHAR(64) NOT NULL,
            `login_at`  INT         NOT NULL,
            `logout_at` INT         NULL,
            PRIMARY KEY (`id`),
            KEY idx_cid (`citizenid`),
            KEY idx_open (`citizenid`, `logout_at`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
    ]])
    migrations.apply('phone_mdt_profile_sessions')

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS phone_mdt_person_records (
            `citizenid`  VARCHAR(64)  NOT NULL,
            `notes`      TEXT         NULL,
            `flags`      TEXT         NULL,
            `mugshot`    VARCHAR(512) NULL,
            `updated_by` VARCHAR(64)  NULL,
            `updated_at` INT          NOT NULL,
            PRIMARY KEY (`citizenid`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
    ]])
    migrations.apply('phone_mdt_person_records')

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS phone_mdt_vehicles (
            `plate`      VARCHAR(16)  NOT NULL,
            `notes`      TEXT         NULL,
            `points`     INT          NOT NULL DEFAULT 0,
            `status`     VARCHAR(16)  NOT NULL DEFAULT 'valid',
            `stolen`     TINYINT(1)   NOT NULL DEFAULT 0,
            `bolo`       TINYINT(1)   NOT NULL DEFAULT 0,
            `image`      VARCHAR(512) NULL,
            `updated_by` VARCHAR(64)  NULL,
            `updated_at` INT          NOT NULL,
            PRIMARY KEY (`plate`),
            KEY idx_flags (`stolen`, `bolo`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
    ]])
    migrations.apply('phone_mdt_vehicles')

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS phone_mdt_offences (
            `code`        VARCHAR(16)  NOT NULL,
            `label`       VARCHAR(120) NOT NULL,
            `class`       VARCHAR(16)  NOT NULL,
            `months`      INT UNSIGNED NOT NULL DEFAULT 0,
            `fine`        INT UNSIGNED NOT NULL DEFAULT 0,
            `description` VARCHAR(255) NOT NULL DEFAULT '',
            PRIMARY KEY (`code`),
            KEY idx_class (`class`),
            KEY idx_label (`label`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
    ]])
    migrations.apply('phone_mdt_offences')
    seedOffences()

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS phone_mdt_reports (
            `id`              INT          NOT NULL AUTO_INCREMENT,
            `ref`             VARCHAR(16)  NOT NULL,
            `title`           VARCHAR(160) NOT NULL,
            `type`            VARCHAR(32)  NOT NULL,
            `body`            MEDIUMTEXT   NULL,
            `author_cid`      VARCHAR(64)  NOT NULL,
            `author_name`     VARCHAR(96)  NOT NULL,
            `author_callsign` VARCHAR(16)  NULL,
            `department`      VARCHAR(64)  NOT NULL DEFAULT '',
            `domain`          VARCHAR(8)   NOT NULL DEFAULT 'leo',
            `created_at`      INT          NOT NULL,
            `updated_at`      INT          NOT NULL,
            PRIMARY KEY (`id`),
            UNIQUE KEY uniq_ref (`ref`),
            KEY idx_created (`created_at`),
            KEY idx_type (`type`),
            KEY idx_domain (`domain`),
            KEY idx_author (`author_cid`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
    ]])
    migrations.apply('phone_mdt_reports')

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS phone_mdt_report_charges (
            `id`        INT          NOT NULL AUTO_INCREMENT,
            `report_id` INT          NOT NULL,
            `citizenid` VARCHAR(64)  NOT NULL,
            `code`      VARCHAR(16)  NOT NULL,
            `label`     VARCHAR(120) NOT NULL,
            `class`     VARCHAR(16)  NOT NULL,
            `count`     INT UNSIGNED NOT NULL DEFAULT 1,
            `months`    INT UNSIGNED NOT NULL DEFAULT 0,
            `fine`      INT UNSIGNED NOT NULL DEFAULT 0,
            PRIMARY KEY (`id`),
            KEY idx_report (`report_id`),
            KEY idx_cid (`citizenid`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
    ]])
    migrations.apply('phone_mdt_report_charges')

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS phone_mdt_report_involved (
            `id`        INT          NOT NULL AUTO_INCREMENT,
            `report_id` INT          NOT NULL,
            `citizenid` VARCHAR(64)  NOT NULL,
            `role`      VARCHAR(16)  NOT NULL,
            `notes`     VARCHAR(255) NULL,
            PRIMARY KEY (`id`),
            UNIQUE KEY uniq_party (`report_id`, `citizenid`, `role`),
            KEY idx_cid (`citizenid`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
    ]])
    migrations.apply('phone_mdt_report_involved')

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS phone_mdt_report_restrictions (
            `id`         INT         NOT NULL AUTO_INCREMENT,
            `report_id`  INT         NOT NULL,
            `type`       VARCHAR(16) NOT NULL,
            `identifier` VARCHAR(64) NOT NULL,
            PRIMARY KEY (`id`),
            UNIQUE KEY uniq_rule (`report_id`, `type`, `identifier`),
            KEY idx_ident (`type`, `identifier`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
    ]])
    migrations.apply('phone_mdt_report_restrictions')

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS phone_mdt_cases (
            `id`           INT          NOT NULL AUTO_INCREMENT,
            `ref`          VARCHAR(16)  NOT NULL,
            `title`        VARCHAR(160) NOT NULL,
            `summary`      TEXT         NULL,
            `status`       VARCHAR(16)  NOT NULL DEFAULT 'open',
            `priority`     VARCHAR(16)  NOT NULL DEFAULT 'medium',
            `department`   VARCHAR(64)  NOT NULL DEFAULT '',
            `created_cid`  VARCHAR(64)  NOT NULL,
            `created_name` VARCHAR(96)  NOT NULL,
            `created_at`   INT          NOT NULL,
            `updated_at`   INT          NOT NULL,
            PRIMARY KEY (`id`),
            UNIQUE KEY uniq_ref (`ref`),
            KEY idx_status (`status`),
            KEY idx_updated (`updated_at`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
    ]])
    migrations.apply('phone_mdt_cases')

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS phone_mdt_case_officers (
            `id`          INT         NOT NULL AUTO_INCREMENT,
            `case_id`     INT         NOT NULL,
            `citizenid`   VARCHAR(64) NOT NULL,
            `role`        VARCHAR(16) NOT NULL DEFAULT 'assisting',
            `assigned_by` VARCHAR(64) NULL,
            `assigned_at` INT         NOT NULL,
            PRIMARY KEY (`id`),
            UNIQUE KEY uniq_officer (`case_id`, `citizenid`),
            KEY idx_cid (`citizenid`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
    ]])
    migrations.apply('phone_mdt_case_officers')

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS phone_mdt_case_notes (
            `id`          INT         NOT NULL AUTO_INCREMENT,
            `case_id`     INT         NOT NULL,
            `author_cid`  VARCHAR(64) NOT NULL,
            `author_name` VARCHAR(96) NOT NULL,
            `body`        TEXT        NOT NULL,
            `created_at`  INT         NOT NULL,
            PRIMARY KEY (`id`),
            KEY idx_case (`case_id`, `created_at`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
    ]])
    migrations.apply('phone_mdt_case_notes')

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS phone_mdt_case_reports (
            `id`        INT NOT NULL AUTO_INCREMENT,
            `case_id`   INT NOT NULL,
            `report_id` INT NOT NULL,
            PRIMARY KEY (`id`),
            UNIQUE KEY uniq_link (`case_id`, `report_id`),
            KEY idx_report (`report_id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
    ]])
    migrations.apply('phone_mdt_case_reports')

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS phone_mdt_warrants (
            `id`              INT          NOT NULL AUTO_INCREMENT,
            `ref`             VARCHAR(16)  NOT NULL,
            `citizenid`       VARCHAR(64)  NOT NULL,
            `subject_name`    VARCHAR(96)  NOT NULL DEFAULT '',
            `report_id`       INT          NULL,
            `report_ref`      VARCHAR(16)  NULL,
            `charges`         TEXT         NULL,
            `felonies`        INT UNSIGNED NOT NULL DEFAULT 0,
            `misdemeanors`    INT UNSIGNED NOT NULL DEFAULT 0,
            `infractions`     INT UNSIGNED NOT NULL DEFAULT 0,
            `bond`            INT UNSIGNED NOT NULL DEFAULT 0,
            `issued_cid`      VARCHAR(64)  NOT NULL,
            `issued_name`     VARCHAR(96)  NOT NULL DEFAULT '',
            `issued_callsign` VARCHAR(16)  NULL,
            `department`      VARCHAR(64)  NOT NULL DEFAULT '',
            `issued_at`       INT          NOT NULL,
            `expiry`          INT          NOT NULL,
            PRIMARY KEY (`id`),
            UNIQUE KEY uniq_ref (`ref`),
            KEY idx_subject (`citizenid`, `expiry`),
            KEY idx_expiry (`expiry`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
    ]])
    migrations.apply('phone_mdt_warrants')

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS phone_mdt_arrests (
            `id`               INT          NOT NULL AUTO_INCREMENT,
            `ref`              VARCHAR(16)  NOT NULL,
            `report_id`        INT          NULL,
            `report_ref`       VARCHAR(16)  NULL,
            `citizenid`        VARCHAR(64)  NOT NULL,
            `subject_name`     VARCHAR(96)  NOT NULL DEFAULT '',
            `officer_cid`      VARCHAR(64)  NOT NULL,
            `officer_name`     VARCHAR(96)  NOT NULL DEFAULT '',
            `officer_callsign` VARCHAR(16)  NULL,
            `charges`          TEXT         NULL,
            `months`           INT UNSIGNED NOT NULL DEFAULT 0,
            `fine`             INT UNSIGNED NOT NULL DEFAULT 0,
            `jailed`           TINYINT(1)   NOT NULL DEFAULT 0,
            `fined`            TINYINT(1)   NOT NULL DEFAULT 0,
            `created_at`       INT          NOT NULL,
            PRIMARY KEY (`id`),
            UNIQUE KEY uniq_ref (`ref`),
            KEY idx_cid (`citizenid`),
            KEY idx_created (`created_at`),
            KEY idx_officer (`officer_cid`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
    ]])
    migrations.apply('phone_mdt_arrests')

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS phone_mdt_enforcement (
            `report_ref` VARCHAR(16) NOT NULL,
            `citizenid`  VARCHAR(64) NOT NULL,
            `jailed`     TINYINT(1)  NOT NULL DEFAULT 0,
            `fined`      TINYINT(1)  NOT NULL DEFAULT 0,
            `arrest_ref` VARCHAR(16) NULL,
            `updated_at` INT         NOT NULL,
            PRIMARY KEY (`report_ref`, `citizenid`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
    ]])
    migrations.apply('phone_mdt_enforcement')

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS phone_mdt_bulletins (
            `id`              INT          NOT NULL AUTO_INCREMENT,
            `title`           VARCHAR(120) NOT NULL,
            `body`            TEXT         NOT NULL,
            `author_cid`      VARCHAR(64)  NOT NULL,
            `author_name`     VARCHAR(96)  NOT NULL DEFAULT '',
            `author_callsign` VARCHAR(16)  NULL,
            `department`      VARCHAR(64)  NOT NULL DEFAULT '',
            `created_at`      INT          NOT NULL,
            `updated_at`      INT          NOT NULL,
            PRIMARY KEY (`id`),
            KEY idx_created (`created_at`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
    ]])
    migrations.apply('phone_mdt_bulletins')

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS phone_mdt_audit (
            `id`             INT         NOT NULL AUTO_INCREMENT,
            `actor_cid`      VARCHAR(64) NOT NULL,
            `actor_name`     VARCHAR(96) NOT NULL DEFAULT '',
            `actor_callsign` VARCHAR(16) NULL,
            `department`     VARCHAR(64) NOT NULL DEFAULT '',
            `action`         VARCHAR(48) NOT NULL,
            `entity_type`    VARCHAR(32) NULL,
            `entity_id`      VARCHAR(64) NULL,
            `details`        TEXT        NULL,
            `created_at`     INT         NOT NULL,
            PRIMARY KEY (`id`),
            KEY idx_actor (`actor_cid`),
            KEY idx_entity (`entity_type`, `entity_id`),
            KEY idx_created (`created_at`),
            KEY idx_action (`action`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
    ]])
    migrations.apply('phone_mdt_audit')

    -- One medical file per citizen, written by the medical terminal and readable by nothing else.
    -- Deliberately NOT part of phone_mdt_person_records: that row is the police sheet, and a
    -- shared table would put an officer one query away from a patient's history.
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS phone_mdt_medical (
            `citizenid`   VARCHAR(64)  NOT NULL,
            `blood_type`  VARCHAR(8)   NOT NULL DEFAULT '',
            `allergies`   VARCHAR(512) NOT NULL DEFAULT '',
            `conditions`  VARCHAR(512) NOT NULL DEFAULT '',
            `medications` VARCHAR(512) NOT NULL DEFAULT '',
            `notes`       MEDIUMTEXT   NULL,
            `dnr`         TINYINT(1)   NOT NULL DEFAULT 0,
            `updated_by`  VARCHAR(96)  NOT NULL DEFAULT '',
            `updated_at`  INT          NOT NULL DEFAULT 0,
            PRIMARY KEY (`citizenid`),
            KEY idx_updated (`updated_at`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
    ]])
    migrations.apply('phone_mdt_medical')

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS phone_mdt_protocols (
            `code`        VARCHAR(16)  NOT NULL,
            `label`       VARCHAR(120) NOT NULL,
            `category`    VARCHAR(24)  NOT NULL,
            `priority`    VARCHAR(16)  NOT NULL DEFAULT 'routine',
            `description` VARCHAR(255) NOT NULL DEFAULT '',
            `body`        MEDIUMTEXT   NULL,
            PRIMARY KEY (`code`),
            KEY idx_category (`category`),
            KEY idx_label (`label`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
    ]])
    migrations.apply('phone_mdt_protocols')

    do
        local i = 1
        while i <= #PROTOCOLS do
            local last = math.min(i + 24, #PROTOCOLS)
            local marks, args = {}, {}
            for n = i, last do
                local p = PROTOCOLS[n]
                marks[#marks + 1] = '(?, ?, ?, ?, ?, ?)'
                args[#args + 1] = p[1]
                args[#args + 1] = p[2]
                args[#args + 1] = p[3]
                args[#args + 1] = p[4]
                args[#args + 1] = p[5]
                args[#args + 1] = p[6]
            end
            MySQL.query.await(
                'INSERT IGNORE INTO phone_mdt_protocols (`code`, `label`, `category`, `priority`, `description`, `body`) VALUES '
                    .. table.concat(marks, ', '),
                args)
            i = last + 1
        end
    end

    -- Referential integrity, added on boot so a later install migrates with no manual SQL. Each
    -- call is a no-op once present, orphans are cleared first, and a type or collation mismatch is
    -- logged and skipped rather than being fatal.
    util.ensureForeignKey('phone_mdt_profile_sessions', 'citizenid', 'phone_mdt_profiles', 'citizenid', 'fk_mdt_sessions_profile')
    util.ensureForeignKey('phone_mdt_report_charges', 'report_id', 'phone_mdt_reports', 'id', 'fk_mdt_charges_report')
    util.ensureForeignKey('phone_mdt_report_involved', 'report_id', 'phone_mdt_reports', 'id', 'fk_mdt_involved_report')
    util.ensureForeignKey('phone_mdt_report_restrictions', 'report_id', 'phone_mdt_reports', 'id', 'fk_mdt_restrictions_report')
    util.ensureForeignKey('phone_mdt_case_officers', 'case_id', 'phone_mdt_cases', 'id', 'fk_mdt_case_officers_case')
    util.ensureForeignKey('phone_mdt_case_notes', 'case_id', 'phone_mdt_cases', 'id', 'fk_mdt_case_notes_case')
    util.ensureForeignKey('phone_mdt_case_reports', 'case_id', 'phone_mdt_cases', 'id', 'fk_mdt_case_reports_case')
    util.ensureForeignKey('phone_mdt_case_reports', 'report_id', 'phone_mdt_reports', 'id', 'fk_mdt_case_reports_report')
end

return schema
