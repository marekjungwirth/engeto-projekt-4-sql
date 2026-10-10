# Engeto SQL projekt – Dostupnost potravin a vývoj mezd v ČR

Projekt analyzuje dostupnost základních potravin v České republice vzhledem k průměrným mzdám v letech **2006–2018** a porovnává tento vývoj s růstem HDP. Všechny dotazy jsou v souboru [`projekt.sql`](projekt.sql) (PostgreSQL), všechna čísla v tomto dokumentu pocházejí z jejich výstupů.

**Obsah repozitáře**

| Soubor | Popis |
|---|---|
| `projekt.sql` | Skript vytvářející obě výstupní tabulky, kontroly kvality dat (DQ1–DQ5) a dotazy k pěti výzkumným otázkám |
| `README.md` | Tento dokument: metodika, informace o datech a odpovědi na otázky |

**Spuštění:** skript se spouští v databázi se zdrojovými tabulkami Engeto (`czechia_payroll`, `czechia_price`, `countries`, `economies` a příslušné číselníky). Tabulky se před vytvořením mažou (`DROP TABLE IF EXISTS`), takže lze skript pouštět opakovaně. Zdrojové tabulky se nijak neupravují.

---

## 1. Výstupní tabulky a metodika

### `t_marek_jungwirth_project_SQL_primary_final`
Mzdy a ceny potravin v ČR za společné roky (2006–2018). Jeden řádek = **rok × odvětví × kategorie potravin**.

- **Mzdy:** `czechia_payroll`, typ hodnoty `5958` (průměrná hrubá mzda na zaměstnance), kalkulace `200` (přepočtený počet), zprůměrováno přes čtvrtletí. Jde o **měsíční hrubou nominální mzdu**.
- **Ceny:** `czechia_price`, zprůměrováno přes týdny a regiony do ročního průměru za kategorii.
- **Propojení** mzdy a cen probíhá jen přes rok. Hodnota mzdy se proto opakuje pro každou kategorii potravin a cena pro každé odvětví. Analytické dotazy proto před počítáním hodnoty deduplikují nebo agregují.
- **„Průměrná mzda“ v ČR** je v otázkách 2, 4 a 5 **prostý (nevážený) průměr přes 19 odvětví**, nikoli vážený počtem zaměstnanců. Hodnoty se tak mohou lišit od oficiálně publikované průměrné mzdy.

### `t_marek_jungwirth_project_SQL_secondary_final`
HDP, GINI koeficient a populace 45 evropských států (`countries.continent = 'Europe'`) ve stejném období jako primární tabulka (2006–2018), celkem 585 řádků. K zodpovězení výzkumných otázek se z ní používá pouze řádek České republiky (otázka 5); ostatní státy slouží jako dodatečný materiál.

---

## 2. Informace o výstupních datech (chybějící hodnoty a omezení)

| Téma | Zjištění | Dopad |
|---|---|---|
| Společné období | Mzdy i ceny se překrývají v letech 2006–2018 (13 let) | Otázka 1 sleduje mzdy jen v tomto období, ne v celé historii dat o mzdách |
| Odvětví (DQ2) | Všech 19 odvětví má data za všech 13 let, bez mezer | Bez omezení |
| Kategorie potravin (DQ1) | 26 z 27 kategorií má data za všech 13 let, **Jakostní víno bílé jen za 2015–2018** | V roce 2015 vstupuje do průměru cen nová, dražší položka a zkresluje meziroční růst cen (viz níže) |
| Mzdy bez odvětví (DQ3) | Ze zdroje bylo vyřazeno **86 řádků** s typem 5958 a kalkulací 200 bez kódu odvětví | Počet odpovídá zhruba 22 letům × 4 čtvrtletí, takže se pravděpodobně jedná o celorepublikový souhrn, nikoli o chybu. Souhrn se nepoužívá, průměr se počítá z odvětví |
| Ceny bez regionu (DQ4) | **7 217 ze 108 249** cenových řádků (6,7 %) nemá region | Řádky jsou zahrnuty do ročního průměru; vliv na průměr je pravděpodobně malý, nebyl ale samostatně testován |
| Sekundární tabulka (DQ5) | Tabulka má **585 řádků** (45 států × 13 let). Chybí **HDP u 37 řádků (6,3 %)** a **GINI u 124 řádků (21,2 %)**, populace je úplná. Chybějící hodnoty zůstávají `NULL` a nijak se nedoplňují | Česká republika má HDP za všech 13 let (jinak by nešel spočítat růst HDP v otázce 5), takže chybějící hodnoty analýzu ČR neovlivňují. U ostatních států je třeba s `NULL` počítat, zejména u GINI |
| Nominální hodnoty | Mzdy i ceny jsou v běžných cenách, bez očištění o inflaci | Růst mezd je třeba číst jako nominální |

### Vliv vína na růst cen (dotaz 4b)
Meziroční růst průměrné ceny počítaný ze všech kategorií je v roce 2015 nadhodnocený, protože tam vstupuje víno. Porovnání s řadou „bez vína“ (*like-for-like*):

| Rok | Růst cen, všechny kategorie | Růst cen bez vína |
|---|---|---|
| 2015 | −0,55 % | **−2,91 %** |
| 2016 | −1,19 % | −1,42 % |
| 2017 | 9,63 % | **10,12 %** |
| 2018 | 2,17 % | 2,08 % |

V letech 2007–2014 jsou obě řady shodné. Otázky 1–3 se vína netýkají (mzdy, absolutní ceny, růst po jednotlivých kategoriích). Otázky 4 a 5 jsou proto vyhodnoceny pro obě řady.

---

## 3. Odpovědi na výzkumné otázky

### Otázka 1: Rostou v průběhu let mzdy ve všech odvětvích, nebo v některých klesají?

**Mzdy nerostou nepřetržitě ve všech odvětvích.** V letech 2007–2018 se vyskytlo **25 meziročních poklesů**, které postihly **16 z 19 odvětví**. Nikdy neklesly mzdy jen v odvětvích *Ostatní činnosti*, *Zdravotní a sociální péče* a *Zpracovatelský průmysl*. Nejčastěji klesaly mzdy v odvětví *Těžba a dobývání* (4× – v letech 2009, 2013, 2014 a 2016).

| Rok | Počet odvětví s poklesem | Největší pokles |
|---|---|---|
| 2009 | 4 | Těžba a dobývání (−3,12 %) |
| 2010 | 3 | Vzdělávání (−1,68 %) |
| 2011 | 4 | Veřejná správa a obrana (−2,27 %) |
| **2013** | **11** | **Peněžnictví a pojišťovnictví (−8,83 %)** |
| 2014 | 1 | Těžba a dobývání (−0,59 %) |
| 2015 | 1 | Výroba a rozvod elektřiny, plynu, tepla a klimatiz. vzduchu (−1,56 %) |
| 2016 | 1 | Těžba a dobývání (−0,57 %) |

- Nejvýraznější je rok **2013**: pokles zasáhl 11 odvětví, kromě peněžnictví (−8,83 %) také např. výrobu a rozvod elektřiny, plynu a tepla (−4,44 %) nebo těžbu (−3,24 %).
- V letech 2007, 2008, 2012, 2017 a 2018 nepoklesla mzda v žádném odvětví.
- Řádek „Doprava a skladování 2011“ s 0,00 % je ve skutečnosti pokles o 0,50 Kč, který se zaokrouhlil na nulu.
- Průměrná mzda napříč odvětvími za sledované období přesto vzrostla (viz otázka 2).

### Otázka 2: Kolik litrů mléka a kilogramů chleba lze koupit za první a poslední srovnatelné období?

Srovnatelné období zahrnuje roky **2006 (první)** a **2018 (poslední)**. Za průměrnou měsíční hrubou mzdu bylo možné koupit:

| | 2006 | 2018 | Změna |
|---|---|---|---|
| Průměrná mzda | 21 165,18 Kč | 33 091,45 Kč | +56,3 % |
| Cena chleba (1 kg) | 16,12 Kč | 24,24 Kč | +50,4 % |
| **Chleba za mzdu** | **1 312 kg** | **1 365 kg** | **+4,0 %** |
| Cena mléka (1 l) | 14,44 Kč | 19,82 Kč | +37,3 % |
| **Mléko za mzdu** | **1 465 l** | **1 669 l** | **+13,9 %** |

Mzdy rostly rychleji než ceny obou potravin, kupní síla se tedy zvýšila: u chleba mírně (+4,0 %), u mléka výrazněji (+13,9 %). Počty jsou zaokrouhleny dolů na celé jednotky.

### Otázka 3: Která kategorie potravin zdražuje nejpomaleji?

| Pořadí | Kategorie | Průměrný meziroční růst ceny |
|---|---|---|
| 1 | **Cukr krystalový** | **−1,92 %** |
| 2 | Rajská jablka červená kulatá | −0,74 % |
| 3 | Banány žluté | +0,81 % |

**Nejnižší průměrný meziroční růst má cukr krystalový (−1,92 %).** Cukr ani rajská jablka v průměru nezdražovala, ale zlevňovala. Pokud hledáme kategorii, která skutečně zdražuje, ale nejpomaleji, jsou to **banány žluté (+0,81 % ročně)**. Průměr je aritmetický průměr meziročních změn; porovnávají se jen po sobě jdoucí roky.

### Otázka 4: Existuje rok, ve kterém byl meziroční nárůst cen potravin výrazně vyšší než růst mezd (o více než 10 p. b.)?

**Ne, žádný takový rok neexistuje.** Největší rozdíl mezi růstem cen a růstem mezd byl v roce **2013 (6,65 p. b.)**.

| Rok | Růst mezd | Růst cen | Rozdíl (p. b.) |
|---|---|---|---|
| 2007 | 6,88 % | 6,76 % | −0,12 |
| 2008 | 7,69 % | 6,19 % | −1,51 |
| 2009 | 3,07 % | −6,41 % | −9,49 |
| 2010 | 1,91 % | 1,94 % | 0,03 |
| 2011 | 2,33 % | 3,35 % | 1,02 |
| 2012 | 2,93 % | 6,73 % | 3,80 |
| **2013** | −1,56 % | 5,10 % | **6,65** |
| 2014 | 2,57 % | 0,74 % | −1,84 |
| 2015 | 2,60 % | −0,55 % | −3,15 |
| 2016 | 3,64 % | −1,19 % | −4,83 |
| 2017 | 6,17 % | 9,63 % | 3,46 |
| 2018 | 7,70 % | 2,17 % | −5,53 |

- Dotaz vrací všechny roky a sloupec `exceeds_10_pp`, který je u všech řádků `false`.
- **Citlivost na víno (4b):** bez vína vychází v roce 2017 růst cen 10,12 %, ale mzdy rostly o 6,17 %, rozdíl je tedy 3,95 p. b. Závěr se nemění. Rok 2013, ve kterém je rozdíl největší, vínem ovlivněn není.
- Otázku jsem vyložil jako rozdíl o více než 10 procentních bodů mezi růstem cen a růstem mezd (průměr všech kategorií vs. průměr mezd napříč odvětvími).

### Otázka 5: Má výška HDP vliv na změny ve mzdách a cenách potravin (ve stejném nebo následujícím roce)?

Meziroční růst v letech 2007–2018 (dotaz 5a). Sloupec „Ceny bez vína“ je řada upravená o kategorii, která existuje až od roku 2015.

| Rok | HDP | Mzdy | Ceny | Ceny bez vína | Mzdy v dalším roce | Ceny v dalším roce |
|---|---|---|---|---|---|---|
| 2007 | 5,57 % | 6,88 % | 6,76 % | 6,76 % | 7,69 % | 6,19 % |
| 2008 | 2,69 % | 7,69 % | 6,19 % | 6,19 % | 3,07 % | −6,41 % |
| 2009 | −4,66 % | 3,07 % | −6,41 % | −6,41 % | 1,91 % | 1,94 % |
| 2010 | 2,43 % | 1,91 % | 1,94 % | 1,94 % | 2,33 % | 3,35 % |
| 2011 | 1,76 % | 2,33 % | 3,35 % | 3,35 % | 2,93 % | 6,73 % |
| 2012 | −0,79 % | 2,93 % | 6,73 % | 6,73 % | −1,56 % | 5,10 % |
| 2013 | −0,05 % | −1,56 % | 5,10 % | 5,10 % | 2,57 % | 0,74 % |
| 2014 | 2,26 % | 2,57 % | 0,74 % | 0,74 % | 2,60 % | −0,55 % |
| 2015 | 5,39 % | 2,60 % | −0,55 % | −2,91 % | 3,64 % | −1,19 % |
| 2016 | 2,54 % | 3,64 % | −1,19 % | −1,42 % | 6,17 % | 9,63 % |
| 2017 | 5,17 % | 6,17 % | 9,63 % | 10,12 % | 7,70 % | 2,17 % |
| 2018 | 3,20 % | 7,70 % | 2,17 % | 2,08 % | – | – |

Pearsonova korelace růstu HDP s růstem mezd a cen (dotaz 5b):

| | Stejný rok | Následující rok |
|---|---|---|
| Mzdy | 0,44 (p ≈ 0,15) | **0,68 (p ≈ 0,02)** |
| Ceny, všechny kategorie | 0,49 (p ≈ 0,11) | −0,03 (p ≈ 0,93) |
| Ceny bez vína | 0,41 (p ≈ 0,18) | −0,04 (p ≈ 0,91) |

*P-hodnoty jsou orientační, dopočítané z tabulky 5a mimo SQL (11 dvojic pro následující rok, 12 pro stejný rok).*

**Závěr**

- **Mzdy:** růst HDP se projevuje v růstu mezd **s ročním zpožděním** (r = 0,68). Tento výsledek je stabilní: po vynechání kteréhokoli jednoho roku zůstává korelace mezi 0,61 a 0,80. Ve stejném roce je vazba slabší a nejistá (r = 0,44).
  - Po silném růstu HDP v roce 2007 (+5,57 %) vzrostly mzdy v roce 2008 o 7,69 %. Po růstu v roce 2017 (+5,17 %) vzrostly mzdy v roce 2018 o 7,70 %.
  - Po růstu HDP v roce 2015 (+5,39 %) mzdy v témže roce nezrychlily (+2,60 % oproti +2,57 % v roce 2014). Zrychlení přišlo až v roce 2016 (+3,64 %).
  - Po poklesu HDP v letech 2012 (−0,79 %) a 2013 (−0,05 %) klesly mzdy v roce 2013 o 1,56 %. Je to jediný rok v datech, kdy klesla průměrná mzda.
- **Ceny potravin:** stabilní vztah k HDP **nevychází**. Zdánlivě středně silná korelace ve stejném roce (r = 0,49) pochází **výhradně z roku 2009** (HDP −4,66 %, ceny −6,41 %). Po vynechání tohoto roku klesá na 0,00. V následujícím roce je korelace nulová (−0,03). Silný růst HDP v letech 2007, 2015 a 2017 provázely ceny +6,76 %, −0,55 % a +9,63 %, tedy bez jednotného směru. Použití řady bez vína závěr nemění.
- **Omezení:** v datech je jen 11–12 pozorování, korelace neznamená příčinnost a ceny potravin ovlivňují i další faktory (zemědělská produkce, počasí, kurz měny, daně), které analýza neobsahuje.

---

## 4. Omezení analýzy (shrnutí)

- Analýza používá **nominální** mzdy a ceny, bez očištění o inflaci.
- „Průměrná mzda“ je nevážený průměr 19 odvětví.
- Průměrná cena „všech potravin“ je prostý průměr cen kategorií s různými jednotkami (kg, l, ks); používá se jen pro meziroční **změny**, nikoli pro úroveň cen.
- Řada všech kategorií je v roce 2015 zkreslená vstupem vína; kontrola je v dotazu 4b a v otázkách 4 a 5.
- Korelace v otázce 5 vychází z malého počtu pozorování (11–12).
