// Hand-curated GPS routes following real Valencia streets.
// Each bot has 2 sub-loops. Adjacent neighborhoods share boundary streets so
// bots naturally contest the same zones. Sub-loop B always overlaps a
// neighbouring bot's territory to create organic conflict.
import 'package:latlong2/latlong.dart';

// All 15 bot UUIDs — must match auth_service.dart and rival_mover_service.dart.
// vBotR_cremaet is the 5th active bot (@Cremaet); routes pending (reuses vBotR3 slot).
const String vBotR1  = '7a4e2c1d-8b3f-4a9e-b5d2-c1e3f4a6b7d8';
const String vBotR2  = '00000000-r002-r002-r002-000000000002';
const String vBotR3  = '00000000-r003-r003-r003-000000000003';
const String vBotRCremaet = '00000000-r003-r003-r003-000000000003'; // same UUID as vBotR3 until own routes are added
const String vBotR4  = '00000000-r004-r004-r004-000000000004';
const String vBotR5  = '00000000-r005-r005-r005-000000000005';
const String vBotR6  = '00000000-r006-r006-r006-000000000006';
const String vBotR7  = '00000000-r007-r007-r007-000000000007';
const String vBotR8  = '00000000-r008-r008-r008-000000000008';
const String vBotR9  = '00000000-r009-r009-r009-000000000009';
const String vBotR10 = '00000000-r010-r010-r010-000000000010';
const String vBotR11 = '3f7b2e4c-9d1a-4e8f-a3c5-b2d4e5f6c7a8';
const String vBotR12 = '00000000-r012-r012-r012-000000000012';
const String vBotR13 = '00000000-r013-r013-r013-000000000013';
const String vBotR14 = '00000000-r014-r014-r014-000000000014';
const String vBotR15 = '00000000-r015-r015-r015-000000000015';

/// Display info: name + hex colour for each bot.
/// Only 2 active bots — matches the website landing page simulation.
/// Others commented out (not deleted) for future re-activation.
const Map<String, Map<String, String>> valenciaRivalInfo = {
  vBotR1:  {'name': '@RitaBarberà',  'color': '#9B59B6'},  // Ruzafa / central
  vBotR2:  {'name': '@Esmorçaet',   'color': '#E83B3B'},  // Malvarrosa / east coast
  // vBotRCremaet: {'name': '@Cremaet', 'color': '#39FF6B'},  // Histórico — activate once routes defined
  // vBotR3:  {'name': 'FALLERA',     'color': '#39FF6B'},
  // vBotR4:  {'name': 'PILOTARI',    'color': '#FF4500'},
  // vBotR5:  {'name': 'TARONGERO',   'color': '#FFD700'},
  // vBotR6:  {'name': 'NINOT',       'color': '#FF69B4'},
  // vBotR7:  {'name': 'SEQUIERO',    'color': '#9370DB'},
  // vBotR8:  {'name': 'ARROSSER',    'color': '#20B2AA'},
  // vBotR9:  {'name': 'MICALET',     'color': '#FF1493'},
  // vBotR10: {'name': 'LLOTGER',     'color': '#00CED1'},
  vBotR11: {'name': '@Club_Babalà',  'color': '#F5A623'},  // Jesús / south
  vBotR12: {'name': '@viscaLesFalles', 'color': '#00B4D8'},  // Campanar / northwest
  // vBotR13: {'name': 'SOROLLÀ',     'color': '#BA55D3'},
  // vBotR14: {'name': 'BARQUERO',    'color': '#F0E68C'},
  // vBotR15: {'name': 'PESCAILLA',   'color': '#7FFFD4'},
};

/// Two sub-loops per bot. After each loop closure the bot randomly switches.
/// Routes follow real Valencia avenues; adjacent bots share at least one street
/// segment so territorial conflict arises organically.
const Map<String, List<List<LatLng>>> valenciaRoutes = {

  // ── r1 NIÑO RATA — Ruzafa ─────────────────────────────────────────────────
  // A: inner Ruzafa grid loop (~C/ Sueca, C/ Ruzafa, C/ dels Tomasos)
  // B: north Ruzafa pushing onto Gran Vía — shares boundary with r9 CARMEN
  vBotR1: [
    [
      const LatLng(39.4638, -0.3742), const LatLng(39.4650, -0.3732),
      const LatLng(39.4662, -0.3720), const LatLng(39.4675, -0.3708),
      const LatLng(39.4685, -0.3695), const LatLng(39.4695, -0.3710),
      const LatLng(39.4702, -0.3728), const LatLng(39.4706, -0.3748),
      const LatLng(39.4700, -0.3762), const LatLng(39.4690, -0.3758),
      const LatLng(39.4678, -0.3752), const LatLng(39.4662, -0.3748),
      const LatLng(39.4648, -0.3745),
    ],
    [
      const LatLng(39.4655, -0.3750), const LatLng(39.4665, -0.3740),
      const LatLng(39.4680, -0.3728), const LatLng(39.4692, -0.3715),
      const LatLng(39.4700, -0.3695), const LatLng(39.4710, -0.3688),
      const LatLng(39.4720, -0.3700), const LatLng(39.4715, -0.3722),
      const LatLng(39.4708, -0.3740), const LatLng(39.4700, -0.3758),
      const LatLng(39.4688, -0.3762), const LatLng(39.4675, -0.3760),
    ],
  ],

  // ── r2 TU EX — Malvarrosa coast ───────────────────────────────────────────
  // A: Malvarrosa beachfront north loop
  // B: south Cabanyal — shares streets with r15 CABANYAL OLD
  vBotR2: [
    [
      const LatLng(39.4792, -0.3275), const LatLng(39.4810, -0.3258),
      const LatLng(39.4825, -0.3245), const LatLng(39.4840, -0.3238),
      const LatLng(39.4842, -0.3252), const LatLng(39.4830, -0.3265),
      const LatLng(39.4815, -0.3272), const LatLng(39.4798, -0.3278),
      const LatLng(39.4780, -0.3288), const LatLng(39.4762, -0.3298),
      const LatLng(39.4748, -0.3312), const LatLng(39.4742, -0.3328),
      const LatLng(39.4750, -0.3340), const LatLng(39.4762, -0.3325),
      const LatLng(39.4775, -0.3305), const LatLng(39.4785, -0.3285),
    ],
    [
      const LatLng(39.4712, -0.3320), const LatLng(39.4725, -0.3305),
      const LatLng(39.4740, -0.3292), const LatLng(39.4758, -0.3280),
      const LatLng(39.4768, -0.3268), const LatLng(39.4762, -0.3248),
      const LatLng(39.4748, -0.3252), const LatLng(39.4735, -0.3265),
      const LatLng(39.4722, -0.3278), const LatLng(39.4710, -0.3295),
      const LatLng(39.4705, -0.3312),
    ],
  ],

  // ── r3 CHAVO DEL 8 — Benimaclet ───────────────────────────────────────────
  // A: Benimaclet university area core loop
  // B: west toward Algirós sharing Blasco Ibáñez with r13 ALGIROS
  vBotR3: [
    [
      const LatLng(39.4840, -0.3562), const LatLng(39.4852, -0.3548),
      const LatLng(39.4862, -0.3532), const LatLng(39.4870, -0.3512),
      const LatLng(39.4865, -0.3496), const LatLng(39.4852, -0.3505),
      const LatLng(39.4840, -0.3520), const LatLng(39.4828, -0.3538),
      const LatLng(39.4820, -0.3555), const LatLng(39.4825, -0.3572),
      const LatLng(39.4835, -0.3568),
    ],
    [
      const LatLng(39.4832, -0.3570), const LatLng(39.4840, -0.3552),
      const LatLng(39.4848, -0.3530), const LatLng(39.4852, -0.3508),
      const LatLng(39.4845, -0.3490), const LatLng(39.4835, -0.3498),
      const LatLng(39.4825, -0.3512), const LatLng(39.4820, -0.3530),
      const LatLng(39.4812, -0.3548), const LatLng(39.4808, -0.3565),
      const LatLng(39.4815, -0.3578), const LatLng(39.4824, -0.3580),
    ],
  ],

  // ── r4 GARROFERA — south-west Valencia ────────────────────────────────────
  // A: Garrofera park inner loop
  // B: east toward Patraix — shared C/ de la Rambleta with r14 PATRAIX
  vBotR4: [
    [
      const LatLng(39.4568, -0.3892), const LatLng(39.4578, -0.3878),
      const LatLng(39.4590, -0.3862), const LatLng(39.4602, -0.3858),
      const LatLng(39.4610, -0.3870), const LatLng(39.4605, -0.3888),
      const LatLng(39.4592, -0.3900), const LatLng(39.4578, -0.3905),
      const LatLng(39.4565, -0.3898),
    ],
    [
      const LatLng(39.4578, -0.3918), const LatLng(39.4590, -0.3905),
      const LatLng(39.4602, -0.3892), const LatLng(39.4615, -0.3882),
      const LatLng(39.4622, -0.3868), const LatLng(39.4618, -0.3850),
      const LatLng(39.4605, -0.3842), const LatLng(39.4590, -0.3848),
      const LatLng(39.4578, -0.3860), const LatLng(39.4568, -0.3875),
      const LatLng(39.4562, -0.3895), const LatLng(39.4568, -0.3910),
    ],
  ],

  // ── r5 MESTALLA — stadium district ────────────────────────────────────────
  // A: loop around Mestalla stadium (Av. Suècia / C/ Dr. Waksman)
  // B: north on Blasco Ibáñez toward Algirós — shared with r13 ALGIROS
  vBotR5: [
    [
      const LatLng(39.4742, -0.3582), const LatLng(39.4752, -0.3568),
      const LatLng(39.4762, -0.3552), const LatLng(39.4772, -0.3540),
      const LatLng(39.4778, -0.3555), const LatLng(39.4772, -0.3572),
      const LatLng(39.4762, -0.3585), const LatLng(39.4750, -0.3595),
      const LatLng(39.4740, -0.3592), const LatLng(39.4735, -0.3580),
    ],
    [
      const LatLng(39.4755, -0.3590), const LatLng(39.4768, -0.3578),
      const LatLng(39.4780, -0.3562), const LatLng(39.4788, -0.3548),
      const LatLng(39.4790, -0.3532), const LatLng(39.4782, -0.3518),
      const LatLng(39.4770, -0.3522), const LatLng(39.4760, -0.3535),
      const LatLng(39.4752, -0.3550), const LatLng(39.4748, -0.3568),
      const LatLng(39.4748, -0.3582),
    ],
  ],

  // ── r6 PEÑAROJA — Quatre Carreres ─────────────────────────────────────────
  // A: Quatre Carreres inner block loop
  // B: outer loop northward touching Ruzafa south — shared with r1 NIÑO RATA
  vBotR6: [
    [
      const LatLng(39.4500, -0.3678), const LatLng(39.4510, -0.3662),
      const LatLng(39.4522, -0.3648), const LatLng(39.4535, -0.3642),
      const LatLng(39.4545, -0.3652), const LatLng(39.4542, -0.3670),
      const LatLng(39.4530, -0.3682), const LatLng(39.4518, -0.3690),
      const LatLng(39.4505, -0.3688),
    ],
    [
      const LatLng(39.4540, -0.3690), const LatLng(39.4552, -0.3678),
      const LatLng(39.4565, -0.3662), const LatLng(39.4575, -0.3648),
      const LatLng(39.4580, -0.3632), const LatLng(39.4572, -0.3618),
      const LatLng(39.4558, -0.3618), const LatLng(39.4545, -0.3628),
      const LatLng(39.4532, -0.3642), const LatLng(39.4520, -0.3655),
      const LatLng(39.4510, -0.3672), const LatLng(39.4502, -0.3688),
    ],
  ],

  // ── r7 NAZARET — port district ────────────────────────────────────────────
  // A: Nazaret inner streets
  // B: north along Av. del Puerto toward Cabanyal — shared with r15 CABANYAL OLD
  vBotR7: [
    [
      const LatLng(39.4478, -0.3412), const LatLng(39.4490, -0.3398),
      const LatLng(39.4505, -0.3385), const LatLng(39.4518, -0.3380),
      const LatLng(39.4525, -0.3392), const LatLng(39.4520, -0.3408),
      const LatLng(39.4508, -0.3422), const LatLng(39.4495, -0.3430),
      const LatLng(39.4482, -0.3425),
    ],
    [
      const LatLng(39.4488, -0.3428), const LatLng(39.4502, -0.3415),
      const LatLng(39.4518, -0.3402), const LatLng(39.4535, -0.3390),
      const LatLng(39.4552, -0.3378), const LatLng(39.4562, -0.3362),
      const LatLng(39.4558, -0.3345), const LatLng(39.4545, -0.3340),
      const LatLng(39.4528, -0.3352), const LatLng(39.4512, -0.3368),
      const LatLng(39.4498, -0.3382), const LatLng(39.4485, -0.3398),
    ],
  ],

  // ── r8 TRINITAT — Poblats Marítims inland ─────────────────────────────────
  // A: inner Trinitat loop
  // B: east toward Cabanyal — shared streets with r15 CABANYAL OLD
  vBotR8: [
    [
      const LatLng(39.4698, -0.3488), const LatLng(39.4710, -0.3472),
      const LatLng(39.4722, -0.3458), const LatLng(39.4732, -0.3448),
      const LatLng(39.4738, -0.3462), const LatLng(39.4732, -0.3478),
      const LatLng(39.4722, -0.3490), const LatLng(39.4710, -0.3502),
      const LatLng(39.4700, -0.3500),
    ],
    [
      const LatLng(39.4710, -0.3502), const LatLng(39.4722, -0.3488),
      const LatLng(39.4735, -0.3472), const LatLng(39.4748, -0.3458),
      const LatLng(39.4758, -0.3442), const LatLng(39.4760, -0.3425),
      const LatLng(39.4752, -0.3412), const LatLng(39.4738, -0.3415),
      const LatLng(39.4725, -0.3428), const LatLng(39.4712, -0.3445),
      const LatLng(39.4702, -0.3462), const LatLng(39.4698, -0.3480),
    ],
  ],

  // ── r9 CARMEN — El Carmen old town ────────────────────────────────────────
  // A: Carmen core (narrow medieval streets, C/ Quart loop)
  // B: south toward Extramurs — shared C/ Guillem de Castro with r10 EXTRAMUROS
  vBotR9: [
    [
      const LatLng(39.4748, -0.3808), const LatLng(39.4758, -0.3795),
      const LatLng(39.4768, -0.3780), const LatLng(39.4775, -0.3765),
      const LatLng(39.4778, -0.3748), const LatLng(39.4772, -0.3738),
      const LatLng(39.4760, -0.3742), const LatLng(39.4750, -0.3755),
      const LatLng(39.4742, -0.3772), const LatLng(39.4738, -0.3790),
      const LatLng(39.4742, -0.3805),
    ],
    [
      const LatLng(39.4740, -0.3810), const LatLng(39.4732, -0.3798),
      const LatLng(39.4722, -0.3785), const LatLng(39.4712, -0.3778),
      const LatLng(39.4702, -0.3782), const LatLng(39.4698, -0.3798),
      const LatLng(39.4702, -0.3812), const LatLng(39.4715, -0.3820),
      const LatLng(39.4728, -0.3818), const LatLng(39.4740, -0.3812),
    ],
  ],

  // ── r10 EXTRAMUROS — Extramurs district ───────────────────────────────────
  // A: Extramurs core (C/ Quart south side, Av. del Oeste)
  // B: north loop toward Carmen — shared C/ Guillem de Castro with r9 CARMEN
  vBotR10: [
    [
      const LatLng(39.4658, -0.3838), const LatLng(39.4670, -0.3822),
      const LatLng(39.4682, -0.3808), const LatLng(39.4692, -0.3798),
      const LatLng(39.4700, -0.3808), const LatLng(39.4696, -0.3822),
      const LatLng(39.4688, -0.3838), const LatLng(39.4678, -0.3848),
      const LatLng(39.4665, -0.3848),
    ],
    [
      const LatLng(39.4672, -0.3850), const LatLng(39.4685, -0.3838),
      const LatLng(39.4698, -0.3822), const LatLng(39.4712, -0.3808),
      const LatLng(39.4722, -0.3798), const LatLng(39.4730, -0.3785),
      const LatLng(39.4728, -0.3772), const LatLng(39.4718, -0.3768),
      const LatLng(39.4705, -0.3775), const LatLng(39.4692, -0.3788),
      const LatLng(39.4678, -0.3802), const LatLng(39.4665, -0.3818),
      const LatLng(39.4658, -0.3832),
    ],
  ],

  // ── r11 JESUS — Jesús district ────────────────────────────────────────────
  // A: Jesús core loop
  // B: north toward Ruzafa — shared C/ de la Reina boundary with r1 NIÑO RATA
  vBotR11: [
    [
      const LatLng(39.4540, -0.3762), const LatLng(39.4552, -0.3748),
      const LatLng(39.4565, -0.3736), const LatLng(39.4578, -0.3732),
      const LatLng(39.4582, -0.3748), const LatLng(39.4578, -0.3762),
      const LatLng(39.4565, -0.3775), const LatLng(39.4552, -0.3778),
      const LatLng(39.4540, -0.3775),
    ],
    [
      const LatLng(39.4565, -0.3778), const LatLng(39.4578, -0.3765),
      const LatLng(39.4592, -0.3752), const LatLng(39.4605, -0.3742),
      const LatLng(39.4618, -0.3740), const LatLng(39.4625, -0.3752),
      const LatLng(39.4618, -0.3768), const LatLng(39.4605, -0.3778),
      const LatLng(39.4592, -0.3785), const LatLng(39.4578, -0.3788),
      const LatLng(39.4565, -0.3785),
    ],
  ],

  // ── r12 CAMPANAR — Campanar NW Valencia ───────────────────────────────────
  // A: Campanar core (C/ Campanar loop)
  // B: south-east toward Av. Pío XII — shared boundary with r8 TRINITAT
  vBotR12: [
    [
      const LatLng(39.4840, -0.3988), const LatLng(39.4852, -0.3972),
      const LatLng(39.4862, -0.3958), const LatLng(39.4870, -0.3945),
      const LatLng(39.4872, -0.3928), const LatLng(39.4862, -0.3920),
      const LatLng(39.4848, -0.3928), const LatLng(39.4838, -0.3942),
      const LatLng(39.4828, -0.3958), const LatLng(39.4825, -0.3975),
      const LatLng(39.4832, -0.3988),
    ],
    [
      const LatLng(39.4842, -0.3978), const LatLng(39.4850, -0.3962),
      const LatLng(39.4858, -0.3942), const LatLng(39.4862, -0.3922),
      const LatLng(39.4858, -0.3902), const LatLng(39.4845, -0.3892),
      const LatLng(39.4832, -0.3898), const LatLng(39.4820, -0.3915),
      const LatLng(39.4815, -0.3935), const LatLng(39.4818, -0.3958),
      const LatLng(39.4828, -0.3972),
    ],
  ],

  // ── r13 ALGIROS — Algirós east-central ────────────────────────────────────
  // A: Algirós core (near C/ Menorca / Av. Blasco Ibáñez)
  // B: west toward Benimaclet sharing Blasco Ibáñez with r3 CHAVO DEL 8
  vBotR13: [
    [
      const LatLng(39.4778, -0.3490), const LatLng(39.4790, -0.3475),
      const LatLng(39.4802, -0.3462), const LatLng(39.4812, -0.3452),
      const LatLng(39.4818, -0.3465), const LatLng(39.4812, -0.3480),
      const LatLng(39.4800, -0.3492), const LatLng(39.4788, -0.3502),
      const LatLng(39.4778, -0.3502),
    ],
    [
      const LatLng(39.4790, -0.3504), const LatLng(39.4802, -0.3490),
      const LatLng(39.4815, -0.3475), const LatLng(39.4825, -0.3460),
      const LatLng(39.4832, -0.3445), const LatLng(39.4830, -0.3428),
      const LatLng(39.4818, -0.3422), const LatLng(39.4805, -0.3428),
      const LatLng(39.4795, -0.3442), const LatLng(39.4785, -0.3458),
      const LatLng(39.4778, -0.3475), const LatLng(39.4775, -0.3492),
    ],
  ],

  // ── r14 PATRAIX — Patraix south-west ──────────────────────────────────────
  // A: Patraix core
  // B: north toward Extramurs — shared C/ de la Encarnación with r10 EXTRAMUROS
  vBotR14: [
    [
      const LatLng(39.4590, -0.3922), const LatLng(39.4602, -0.3908),
      const LatLng(39.4615, -0.3896), const LatLng(39.4625, -0.3886),
      const LatLng(39.4628, -0.3872), const LatLng(39.4620, -0.3860),
      const LatLng(39.4608, -0.3858), const LatLng(39.4596, -0.3868),
      const LatLng(39.4585, -0.3882), const LatLng(39.4582, -0.3898),
      const LatLng(39.4588, -0.3914),
    ],
    [
      const LatLng(39.4602, -0.3918), const LatLng(39.4618, -0.3905),
      const LatLng(39.4632, -0.3892), const LatLng(39.4645, -0.3882),
      const LatLng(39.4655, -0.3875), const LatLng(39.4658, -0.3860),
      const LatLng(39.4648, -0.3848), const LatLng(39.4635, -0.3848),
      const LatLng(39.4622, -0.3855), const LatLng(39.4608, -0.3868),
      const LatLng(39.4598, -0.3882), const LatLng(39.4595, -0.3900),
    ],
  ],

  // ── r15 CABANYAL OLD — Cabanyal historic ──────────────────────────────────
  // A: Cabanyal historic district (C/ de la Reina / C/ dels Pescadors)
  // B: south toward Nazaret along Av. del Puerto — shared with r7 NAZARET
  vBotR15: [
    [
      const LatLng(39.4720, -0.3360), const LatLng(39.4732, -0.3345),
      const LatLng(39.4745, -0.3332), const LatLng(39.4758, -0.3322),
      const LatLng(39.4768, -0.3332), const LatLng(39.4762, -0.3348),
      const LatLng(39.4750, -0.3360), const LatLng(39.4738, -0.3370),
      const LatLng(39.4725, -0.3370),
    ],
    [
      const LatLng(39.4715, -0.3368), const LatLng(39.4702, -0.3358),
      const LatLng(39.4688, -0.3348), const LatLng(39.4675, -0.3342),
      const LatLng(39.4665, -0.3348), const LatLng(39.4658, -0.3362),
      const LatLng(39.4662, -0.3378), const LatLng(39.4675, -0.3385),
      const LatLng(39.4690, -0.3382), const LatLng(39.4705, -0.3375),
      const LatLng(39.4718, -0.3368),
    ],
  ],
};
