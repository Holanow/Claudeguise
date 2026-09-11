# God-Guise
A Roguelike Autobattler 

**Overview**  
God Guise (Working Title) is a roguelike auto-battler where the player acts as a battlefield coach, issuing plans of action to a party of up to 4 “Pawns”. Each pawn has different capabilities, strengths and weaknesses, can be outfitted with new equipment, and can learn new skills and abilities.

The goal of the player is to have the party advance to the bottom of a 7 level dungeon. Each level consists of 8-20 rooms and each room contains an assortment of enemies, traps, and/or loot. Each level will also have a boss. There will also be shops between each level.

After reaching the bottom of the dungeon the player will be given the option to fight their way back up all 7 levels. (Secret levels, escape to the outside?)

**Pawns**  
Pawns will each come with a random “Class”. Each class will come with “Tags” that determine the skills and equipment a pawn can use. 

Pawns will have a health that determines how much damage they can take and a secondary resource that determines how often they can use their more powerful abilities.

**Mana \-** Large pool that recharges slowly; spent on most abilities  
**Rage** \- Small pool that fills as the pawn attacks; spent on finisher abilities  
**Energy \-** Small pool that recharges quickly; Spent on most abilities

Pawns will also come with a set of base stats that determine the effectiveness of skills they use and their baseline durability.

**Strength (STR) \-** Determines the baseline damage of most melee attacks; slightly increases health  
**Dexterity (DEX)** \- Determines the baseline damage of most ranged attacks; slightly increases movement speed  
**Agility (AGI)** \- Determines pawn movement and action speed  
**Constitution (CON)** \- Determines pawn health  
**Intelligence (INT)** \- Determines the baseline damage of most magical attacks; slightly increases maximum resource  
**Attunement (ATN)** \- Determines pawn maximum resource  

The player will start with one pawn. Pawns will be found as rewards within the dungeon and in shops between stores. Sometimes unique classes will appear on lower-floor pawns.

Pawns will have room to equip 5 items: a main hand, an off hand, a head, a body, and an accessory. This equipment will be found throughout the dungeon as rewards and in the shops between floors. The type of equipment a pawn can use will be governed by their class.

The actions each pawn takes will be decided by their Plans of Action. Plans of action are scripts run under specific circumstances. The scripts will be built out of different “Blocks”, with no cap on the number of blocks in a script. Plans of action are prioritized for execution based on their ordering. Each pawn will have a base set of default behaviors for when no plan of action is active. 

**Classes**  
Classes are fundamentally just a collection of tags, a base attribute distribution, and a set of starting skills. Tags determine the skills and equipment a pawn with a certain class has access to. Classes also determine the resource that a pawn has access to. A pawn can only have one class and the class of a pawn cannot change once it is generated. 

| Tags | | | |
| ----- | ----- | ----- | ----- |
| Method | Style | Damage Type | Role |
| Martial, Magical | Melee, Ranged, Summoner | Physical, Fire, Water, Air, Earth, Divine, Profane, Raw | DPS, Support, Anti-Support, Tank, Healer |

**Martial** - Skill damage heavily determined by weapon, single abilities scale very high
**Magical** - Skills synergize with other skills, Weapons provide unique abilities, very stat reliant
**Melee** - Damage is dealt in close quarters, tankier in general
**Ranged** - Damage is dealt at range
**Summoner** - Damage is dealt by proxies, squishier in general
**DPS** - Primarily is meant to deal heavy damage
**Support** - Primarily meant to buff allies 
**Anti-Support** - Primarily meant to weaken enemies
**Tank** - Meant to actively draw aggro and take damage
**Healer** - Meant to restore health and revive allies

Damage types will have a positive and negative secondary effect associated with them.
**Physical:** Shield, Bleed
**Fire:** Enrage, Burn
**Water:** Cleanse, Soak
**Air:** Haste, Knockback
**Earth:** Block, Stun
**Divine:** Heal, Marked
**Profane:** Debuff Transfer, Poision
**Raw:** Effect Nullifcation

| Classes |  |  |  |  |  |  |  |  |
| :---: | ----- | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| Name | Tags | Str | Dex | Agi | Int | Att | Resource |
| Warrior | Martial, Melee, Physical, Earth, Tank, DPS |  |  |  |  |  | Rage |
| Priest | Magical, Ranged, Divine, Air, Support, Healer  |  |  |  |  |  | Mana |
| Geysermancer | Magical, Ranged, Water, Fire, DPS, Support | | | | | | Mana |
| Siege Master | Martial, Summoner, Physical, Raw, DPS, Anti-Support | | | | | | Energy |
| Abomination | Magical, Melee, Profane, Fire, Anti-Support, Tank | | | | | | Rage |


**Equipment**  
Pawns equip 5 items: **main hand, off hand, head, body, accessory**. Every slot is open from the moment a pawn is acquired. Early floors present few decisions because the player has found few items, not because slots are shut.

Equipment gates on **coarse tags only**: Method (Martial / Magical) crossed with Style (Melee / Ranged / Summoner). This exists solely to stop a Warrior equipping a wand.

Fine-grained tags — Fire, Divine, Physical, Profane, Raw and the rest — are **not** equipment gates. They are synergy hooks that affixes, uniques and skills reference. A "+20% Fire damage" affix finds the Geysermancer and the Abomination without either being locked out of a base type.

Equipment requiring more tags is *not* inherently stronger. Tag counts are unevenly distributed across classes, so that rule would permanently advantage whichever class happens to carry the most tags.

All equipment is visible on the pawn, aside from the helmet. Classes will be differentiated visually by some cosmetic headwear.

**Weapons**

Martial weapons determine the base damage and attack speed for martial skills.
Magical Weapons provide more bonuses and special affects for the pawn's skills.

Some weapons are **two-handed**: they occupy the off hand slot as well, have higher base values, and in exchange roll higher affix ranges than one-handed options.

Weapons all grant an action that serves as the pawn's "basic attack". Any properties of that weapon's attack are really just properties of the action that weapon grants. 

**Affixes**

Four rarities determine affix count (1–4). Affix pools are **scoped by slot** — a helm rolls from its own list, not a global one — and ranges scale by slot, so a body always beats a ring at +HP.

Affixes split into two kinds:

| Kind | Examples | Behavior |
| ----- | ----- | ----- |
| Numbers | +HP, +damage, +crit, resists | Invisible, auto-equippable. Exist to make loot feel good. |
| Verbs | Leech, cooldown recovery, resource-on-kill, on-hit triggers | Change what a pawn *does*. Unlock at deeper floors. |

Floor 1 rolls numbers only.

Passive verbs never appear in the block palette. They appear as a read-only **trait strip** on the pawn card in the Plan editor, so the player can see what changes their scripting math without cluttering the palette. Passive procs must be visible in the combat log during the watch phase.

**Uniques**

Two distinct kinds, both at top rarity. An item is never both.

- **Build-arounds** — break exactly one rule, average or below-average raw stats. The cost must be felt. Build-arounds require their enabler to be present in the run's drop pool, or they are lottery tickets that lose.
- **Chase items** — large numbers, no special rule, no rider.

**Drops**

Every fight on floor 1 drops **1 to 3 items**. Every drop batch guarantees at least one item usable by a current pawn; the rest rolls free. Weighting reads **pawn scaling, not equipped gear**, to avoid runs converging on whatever the player found first.

**Floor 1 Base Types**

Accessory slot deliberately empty pending accessory design. Head and body have no inherent qualities — they are affix sticks.

| Main Hand | Requires | Hands | Character |
| ----- | ----- | ----- | ----- |
| Sword | Martial, Melee | One | Light. Fast, lower damage per hit, higher raw DPS. |
| Mace | Martial, Melee | One | Heavy. Slow, higher damage per hit, armor break on hit. |
| Rune Gauntlet | Magical, Melee | One | Light. Magical counterpart to the Sword. |
| Reaper | Magical, Melee | Two | Scythe. Chance to bleed on hit. |
| Wand | Magical, Ranged | One | Basic attack grants resource on hit. |
| Staff | Magical, Ranged | Two | Basic attack, +30% magical damage. |

| Off Hand | Requires | Grants | Character |
| ----- | ----- | ----- | ----- |
| Tower Shield | Melee | Directional Block | Flat damage reduction. |
| Standard | Melee | Rallying Cry | Places a banner; AoE ally buff in radius. |
| Orb | Magical, Ranged | Channel Mana | Also raises maximum mana. |
| Book | Magical, Ranged | — | Reduces ability cooldown time. |

| Body | Requires |
| ----- | ----- |
| Plate Mail | Melee |
| Robes | Magical, Ranged |

| Head | Requires |
| ----- | ----- |
| Great Helm | Melee |
| Hood | Magical, Ranged |

**Plans of Action**  
Plans of action are short scripts that dictate what a pawn will do in a given situation. The plans are set up by the players using “Blocks” and will be prioritized in some way. Each plan of action starts with a conditional of some kind (i.e. when you see an enemy). There is currently no cap on the number of blocks in a plan. A block can be either a “Targeting”, an “Action” block, or a “Duration” block. Targeting blocks execute instantly under most circumstances and set a pawn’s focus to a certain position (i.e the nearest enemy), Action blocks make the pawn actually do something(i.e. Move, fireball, attack, block) and they tend to have an activation time. Duration blocks affect how long an action is taken for (i.e forever, until you are no longer in range of an area attack)

A pawn can have any number of plans of action set up at any given time. However, conditions and blocks must be found as loot within the dungeon or shops and cannot be shared between pawns once acquired. In addition to their default behaviors, pawns will come with a number of Plans of Action already set up when they are acquired. 

When a pawn has multiple plans of action that would trigger simultaneously, only one triggers. The one that triggers is determined by its priority. 

Ideally a player won’t *have* to interact with this system until they beat the final boss. Though they will still be able to if they are interested. Upon receiving the final boss, the player will receive **The God Guise,** an item that allows them to use any condition without having to find it and more finely tune the attributes of their blocks to encourage them to learn the system for the harder levels to come. 

**Floors**  
There will be 7 floors. Each floor will have a different theme(bgm, tilesets, enemies). Each floor will also have a number of rooms, starting with 8 for the first floor and slowly increasing until the 20 room long 7th floor. Each floor will be procedurally generated, but the layouts of each floor are preserved on ascent and descent.

Each floor will also have a miniboss that will offer disproportionate rewards if defeated. 

**Enemy Room \-** A room containing an assortment of enemies  
**Big Enemy Room \-** A large room containing an assortment of enemies  
**Treasure Room \-** A room containing new equipment for pawns and currency  
**Library** \- A room containing new Plans of Action conditions  
**Cell \-** A room containing a selection of new pawns (pick one)  
**Miniboss Room \-** A room containing a mini boss and disproportionate rewards  
**Boss Room \-** A room containing a floor boss

| Floor | Theme | Boss | Miniboss |
| :---: | ----- | ----- | ----- |
| 1 | Dungeon | The Warden | Rat King |
| 2 | Subterra | The Mad Mole | Feral Greatworm |
| 3 | Aquatica | The School | Undine |
| 4 | The Molten Core | Magmaster | Collapsing Lava Chamber |
| 5 | The Sky Below | The Last Dragon | Valkyrie Legion |
| 6 | Gehenna | Astariel, Fallen Angel | Orthrus |
| 7 | The Dark | The Empty Liege | Shadows |

Between each floor there is a shop containing 1 new pawn, as well as a selection of abilities or equipment. After defeating The Empty Liege the dungeon inverts and the player must climb back up the levels. On the climb back up the levels remain the same,.however the difficulty continues to increase. The return to the 1st floor will consist of a boss rush followed by a special final boss. **The Gate Guardian**

**Enemies**  
The player will fight a number of enemies throughout the dungeon. While the rooms are procedurally generated, the types of enemies within the room will be consistent, only changing on the climb back up. Enemies will have visible health and tags and fairly simple combat patterns on an individual level.

The available enemies will change on each floor and generally their combat patterns should grow more complicated and sophisticated as the player descends. 

Minibosses will have greater health and more complicated patterns, as well as traps placed within their arena.

Bosses will have greater health, 3 phases across which their patterns change, traps placed within their arena, and some subset of minions. 

| Bosses | |
| ----- | ----- |
| Name | Description |
| The Warden | Very standard jail boss, big, slow, scary, can give party members balls and chains and handcuffs, wields an executioner's axe that can do a ton of damage at close range |
| The Mad Mole | Big Mole, A lot of idle time as it digs around, targets the first pawn to do something while it is underground and remains surfaced for a while before running away |
| The School | A big collection of fish that split up into more fish when attacked. The big collection will have ranged attacks while the little children are rushdown melee fighters |  
| Magmaster | Large spinning vat of magma that sucks up magma and spits it back at the party, creates damaging terrain, will also heal from magma? |
| The Last Dragon | No frills fight against a big ass dragon with a solid set of ranged, melee, and crowd control options as well as an above-average AI |
| Astariel, Fallen Angel | Edgy angel vibes, think thanatos from hades. Has an enrage mechanic where the fight will be lost if not completed in a certain amount of time, otherwise very similar to The Last Dragon but with minions |
| The Empty Liege | The sillouhette of a king (maybe a character from later levels), Can dominate specific party members and use them as minions. | 

| Mini-Bosses | |
| ----- | ----- |
| Name | Description |
| The Rat King | Big collection of rats joined at the tail. Ranged attacker, all attacks leave behind rats which are close range melee attackers |
| Feral Greatworm | Big Worm, When it reaches half health it will split into two enemies, this can happen to each secion 3 times for a maximum of 8 worm chunks |
| Undine | A sniper type enemy with powerful ranged attacks that teleports around a very difficult to navigate arena |  
| Collapsing Lava Chamber | A big trap room with a timer |
| Valkyrie Legion | A well-composed party of 4 valkyries, a healer, a ranged damage dealer, and 2 melee damage dealers |
| Orthrus | Big doggo, one body, two heads, figure it out|
| Shadows | A copy of the party with boosted base stats, no equipment, and default plans of action | 
