-- SEED CONTENT — every value must be source-checked by a human before the
-- list is enabled; lists are inserted with enabled=false.
--
-- Re-runnable: safe to apply multiple times (on conflict do nothing).

begin;

insert into public.lists (id, prompt_template, unit, direction, ascending, enabled) values
  (1,  'Order these by the year they were invented',              'year',           'Earliest at the top', true,  false),
  (2,  'Order these by distance from the Sun',                    'AU',             'Closest at the top',  true,  false),
  (3,  'Order these mountains by height',                         'm',              'Tallest at the top',  false, false),
  (4,  'Order these buildings by height',                         'm',              'Tallest at the top',  false, false),
  (5,  'Order these countries by land area',                      'km²',            'Largest at the top',  false, false),
  (6,  'Order these films by the year they were released',        'year',           'Earliest at the top', true,  false),
  (7,  'Order these rivers by length',                             'km',            'Longest at the top',  false, false),
  (8,  'Order these by atomic number',                             'atomic number',  'Lowest at the top',   true,  false),
  (9,  'Order these novels by the year they were first published','year',           'Earliest at the top', true,  false),
  (10, 'Order these cities by the year they hosted the Summer Olympics', 'year',    'Earliest at the top', true,  false),
  (11, 'Order these animals by their typical top speed',           'km/h',          'Fastest at the top',  false, false),
  (12, 'Order these US states by the year they joined the Union',  'year',          'Earliest at the top', true,  false)
on conflict (id) do nothing;

-- list_items are appended below, one list per block.

-- 1. Inventions by year first invented/demonstrated
insert into public.list_items (list_id, label, value, source_url, familiarity, fact) values
  (1, 'Papermaking',            105,  'https://en.wikipedia.org/wiki/Papermaking', 2, 'Traditionally credited to Han dynasty official Cai Lun.'),
  (1, 'Gunpowder',               850, 'https://en.wikipedia.org/wiki/Gunpowder', 2, 'First recorded in Tang dynasty Chinese alchemical texts.'),
  (1, 'Movable type printing',  1040, 'https://en.wikipedia.org/wiki/Movable_type', 3, 'Bi Sheng made ceramic type during China''s Song dynasty.'),
  (1, 'Eyeglasses',             1286, 'https://en.wikipedia.org/wiki/Glasses', 2, 'First produced by Italian craftsmen to correct eyesight.'),
  (1, 'Printing press',         1440, 'https://en.wikipedia.org/wiki/Printing_press', 1, 'Johannes Gutenberg''s press launched mass printing in Europe.'),
  (1, 'Telescope',              1608, 'https://en.wikipedia.org/wiki/Telescope', 1, 'Hans Lippershey filed the first known patent for one.'),
  (1, 'Steam engine',           1712, 'https://en.wikipedia.org/wiki/Newcomen_atmospheric_engine', 2, 'Thomas Newcomen built the first practical version.'),
  (1, 'Lightning rod',          1752, 'https://en.wikipedia.org/wiki/Lightning_rod', 2, 'Benjamin Franklin proposed it to protect buildings from strikes.'),
  (1, 'Bicycle',                1817, 'https://en.wikipedia.org/wiki/Bicycle', 1, 'Karl Drais rode his steerable two-wheeled "running machine".'),
  (1, 'Photography',            1826, 'https://en.wikipedia.org/wiki/History_of_photography', 1, 'Nicephore Niepce captured the earliest surviving photograph.'),
  (1, 'Telegraph',              1837, 'https://en.wikipedia.org/wiki/Electrical_telegraph', 2, 'Cooke and Wheatstone patented an early working system.'),
  (1, 'Telephone',              1876, 'https://en.wikipedia.org/wiki/Telephone', 1, 'Alexander Graham Bell received the first US patent.'),
  (1, 'Light bulb',             1879, 'https://en.wikipedia.org/wiki/Incandescent_light_bulb', 1, 'Thomas Edison demonstrated a long-lasting carbon-filament bulb.'),
  (1, 'Automobile',             1886, 'https://en.wikipedia.org/wiki/Car', 1, 'Karl Benz patented the Benz Patent-Motorwagen.'),
  (1, 'Radio',                  1895, 'https://en.wikipedia.org/wiki/Radio', 1, 'Guglielmo Marconi sent the first long-distance signals.'),
  (1, 'Airplane',                1903, 'https://en.wikipedia.org/wiki/Wright_Flyer', 1, 'The Wright brothers flew the first powered aircraft.'),
  (1, 'Zipper',                 1913, 'https://en.wikipedia.org/wiki/Zipper', 2, 'Gideon Sundback patented the modern slide fastener design.'),
  (1, 'Television',             1927, 'https://en.wikipedia.org/wiki/History_of_television', 1, 'Philo Farnsworth demonstrated the first fully electronic system.'),
  (1, 'Ballpoint pen',          1938, 'https://en.wikipedia.org/wiki/Ballpoint_pen', 2, 'Laszlo Biro patented his quick-drying ink pen design.'),
  (1, 'Microwave oven',         1946, 'https://en.wikipedia.org/wiki/Microwave_oven', 1, 'Percy Spencer patented cooking with microwave radiation.')
on conflict (list_id, label) do nothing;

-- 2. Planets and dwarf planets by mean distance from the Sun (AU)
insert into public.list_items (list_id, label, value, source_url, familiarity, fact) values
  (2, 'Mercury',   0.39, 'https://en.wikipedia.org/wiki/Mercury_(planet)', 1, 'The closest planet to the Sun.'),
  (2, 'Venus',     0.72, 'https://en.wikipedia.org/wiki/Venus', 1, 'The hottest planet due to its thick atmosphere.'),
  (2, 'Earth',     1.00, 'https://en.wikipedia.org/wiki/Earth', 1, 'The only known planet with life.'),
  (2, 'Mars',      1.52, 'https://en.wikipedia.org/wiki/Mars', 1, 'Known as the Red Planet for its iron oxide surface.'),
  (2, 'Vesta',     2.36, 'https://en.wikipedia.org/wiki/4_Vesta', 3, 'One of the largest objects in the asteroid belt.'),
  (2, 'Ceres',     2.77, 'https://en.wikipedia.org/wiki/Ceres_(dwarf_planet)', 2, 'The largest object in the asteroid belt.'),
  (2, 'Hygiea',    3.14, 'https://en.wikipedia.org/wiki/10_Hygiea', 3, 'The fourth-largest object in the asteroid belt.'),
  (2, 'Jupiter',   5.20, 'https://en.wikipedia.org/wiki/Jupiter', 1, 'The largest planet in the Solar System.'),
  (2, 'Saturn',    9.58, 'https://en.wikipedia.org/wiki/Saturn', 1, 'Famous for its prominent ring system.'),
  (2, 'Uranus',    19.2, 'https://en.wikipedia.org/wiki/Uranus', 1, 'It rotates almost on its side.'),
  (2, 'Neptune',   30.1, 'https://en.wikipedia.org/wiki/Neptune', 1, 'The windiest planet in the Solar System.'),
  (2, 'Pluto',     39.5, 'https://en.wikipedia.org/wiki/Pluto', 1, 'Reclassified as a dwarf planet in 2006.'),
  (2, 'Haumea',    43.1, 'https://en.wikipedia.org/wiki/Haumea', 3, 'A dwarf planet shaped like an elongated ellipsoid.'),
  (2, 'Quaoar',    43.7, 'https://en.wikipedia.org/wiki/50000_Quaoar', 3, 'A dwarf-planet candidate beyond Neptune''s orbit.'),
  (2, 'Makemake',  45.8, 'https://en.wikipedia.org/wiki/Makemake', 3, 'A dwarf planet named after a Rapa Nui creator god.'),
  (2, 'Gonggong',  67.4, 'https://en.wikipedia.org/wiki/225088_Gonggong', 3, 'A dwarf-planet candidate with a highly tilted orbit.'),
  (2, 'Eris',      67.8, 'https://en.wikipedia.org/wiki/Eris_(dwarf_planet)', 3, 'Its discovery prompted the 2006 redefinition of "planet".'),
  (2, 'Sedna',     506,  'https://en.wikipedia.org/wiki/90377_Sedna', 3, 'One of the most distant known objects in the Solar System.')
on conflict (list_id, label) do nothing;

-- 3. Mountains by height (m)
insert into public.list_items (list_id, label, value, source_url, familiarity, fact) values
  (3, 'Everest',           8849, 'https://en.wikipedia.org/wiki/Mount_Everest', 1, 'The highest mountain above sea level on Earth.'),
  (3, 'K2',                8611, 'https://en.wikipedia.org/wiki/K2', 2, 'The second-highest mountain, on the China-Pakistan border.'),
  (3, 'Nanga Parbat',      8126, 'https://en.wikipedia.org/wiki/Nanga_Parbat', 3, 'The ninth-highest mountain, nicknamed "Killer Mountain".'),
  (3, 'Aconcagua',         6961, 'https://en.wikipedia.org/wiki/Aconcagua', 2, 'The highest peak in South America and the Western Hemisphere.'),
  (3, 'Denali',            6190, 'https://en.wikipedia.org/wiki/Denali', 2, 'The highest peak in North America.'),
  (3, 'Mount Kenya',       5199, 'https://en.wikipedia.org/wiki/Mount_Kenya', 2, 'Africa''s second-highest peak after Kilimanjaro.'),
  (3, 'Kilimanjaro',       5895, 'https://en.wikipedia.org/wiki/Mount_Kilimanjaro', 1, 'The highest peak in Africa.'),
  (3, 'Mont Blanc',        4809, 'https://en.wikipedia.org/wiki/Mont_Blanc', 2, 'The highest peak in the Alps.'),
  (3, 'Mauna Kea',         4207, 'https://en.wikipedia.org/wiki/Mauna_Kea', 2, 'Measured from its base on the ocean floor, it is Earth''s tallest.'),
  (3, 'Mount Fuji',        3776, 'https://en.wikipedia.org/wiki/Mount_Fuji', 1, 'Japan''s highest and most iconic peak.'),
  (3, 'Mount Olympus',     2917, 'https://en.wikipedia.org/wiki/Mount_Olympus', 2, 'The mythical home of the twelve Olympian gods.'),
  (3, 'Mount Kosciuszko',  2228, 'https://en.wikipedia.org/wiki/Mount_Kosciuszko', 2, 'The highest peak on the Australian mainland.'),
  (3, 'Mount Washington',  1917, 'https://en.wikipedia.org/wiki/Mount_Washington_(New_Hampshire)', 3, 'Known for some of the world''s most extreme recorded weather.'),
  (3, 'Ben Nevis',         1345, 'https://en.wikipedia.org/wiki/Ben_Nevis', 2, 'The highest peak in the British Isles.'),
  (3, 'Table Mountain',    1085, 'https://en.wikipedia.org/wiki/Table_Mountain', 2, 'A flat-topped mountain overlooking Cape Town.'),
  (3, 'Uluru',              863, 'https://en.wikipedia.org/wiki/Uluru', 2, 'A large sandstone rock formation in central Australia.'),
  (3, 'Sugarloaf Mountain', 396, 'https://en.wikipedia.org/wiki/Sugarloaf_Mountain', 2, 'A granite peak overlooking Rio de Janeiro''s harbor.'),
  (3, 'Arthur''s Seat',     251, 'https://en.wikipedia.org/wiki/Arthur%27s_Seat', 3, 'An extinct volcano overlooking Edinburgh, Scotland.')
on conflict (list_id, label) do nothing;

-- 4. Famous tall buildings by height (m)
insert into public.list_items (list_id, label, value, source_url, familiarity, fact) values
  (4, 'Burj Khalifa',        828,  'https://en.wikipedia.org/wiki/Burj_Khalifa', 1, 'The tallest building in the world, in Dubai.'),
  (4, 'Shanghai Tower',      632,  'https://en.wikipedia.org/wiki/Shanghai_Tower', 2, 'China''s tallest building, with a twisting facade.'),
  (4, 'Abraj Al Bait',       601,  'https://en.wikipedia.org/wiki/Abraj_Al_Bait', 3, 'A clock tower complex overlooking the Great Mosque in Mecca.'),
  (4, 'One World Trade Center', 541, 'https://en.wikipedia.org/wiki/One_World_Trade_Center', 1, 'The tallest building in the Western Hemisphere.'),
  (4, 'Taipei 101',          508,  'https://en.wikipedia.org/wiki/Taipei_101', 2, 'Once the world''s tallest, with a pagoda-inspired design.'),
  (4, 'Petronas Towers',     452,  'https://en.wikipedia.org/wiki/Petronas_Towers', 1, 'Twin towers that were once the world''s tallest buildings.'),
  (4, 'Willis Tower',        442,  'https://en.wikipedia.org/wiki/Willis_Tower', 1, 'Long the tallest building in the US, in Chicago.'),
  (4, 'Empire State Building', 381, 'https://en.wikipedia.org/wiki/Empire_State_Building', 1, 'An Art Deco icon, once the world''s tallest building.'),
  (4, 'Eiffel Tower',        330,  'https://en.wikipedia.org/wiki/Eiffel_Tower', 1, 'An iron lattice tower built for the 1889 Paris World''s Fair.'),
  (4, 'Chrysler Building',   319,  'https://en.wikipedia.org/wiki/Chrysler_Building', 1, 'An Art Deco skyscraper famed for its stainless-steel spire.'),
  (4, 'Gateway Arch',        192,  'https://en.wikipedia.org/wiki/Gateway_Arch', 2, 'A stainless-steel arch in St. Louis, the tallest arch on Earth.'),
  (4, 'Space Needle',        184,  'https://en.wikipedia.org/wiki/Space_Needle', 1, 'Built for the 1962 World''s Fair in Seattle.'),
  (4, 'Washington Monument', 169,  'https://en.wikipedia.org/wiki/Washington_Monument', 1, 'An obelisk honoring George Washington in Washington, D.C.'),
  (4, 'Great Pyramid of Giza', 147, 'https://en.wikipedia.org/wiki/Great_Pyramid_of_Giza', 1, 'The oldest and largest of the Giza pyramids, built as a tomb.'),
  (4, 'Blackpool Tower',     158,  'https://en.wikipedia.org/wiki/Blackpool_Tower', 2, 'A tourist tower in England inspired by the Eiffel Tower.'),
  (4, 'Elizabeth Tower',      96,  'https://en.wikipedia.org/wiki/Elizabeth_Tower', 1, 'The clock tower at the Houses of Parliament, home of Big Ben.'),
  (4, 'Leaning Tower of Pisa', 57, 'https://en.wikipedia.org/wiki/Leaning_Tower_of_Pisa', 1, 'A medieval bell tower famous for its unintended tilt.'),
  (4, 'Statue of Liberty',    46, 'https://en.wikipedia.org/wiki/Statue_of_Liberty', 1, 'A copper statue in New York Harbor, a gift from France.')
on conflict (list_id, label) do nothing;

-- 5. Countries by land area (km^2), rounded to thousands
insert into public.list_items (list_id, label, value, source_url, familiarity, fact) values
  (5, 'Russia',        17098000, 'https://en.wikipedia.org/wiki/Russia', 1, 'The largest country in the world by far, spanning 11 time zones.'),
  (5, 'Canada',         9985000, 'https://en.wikipedia.org/wiki/Canada', 1, 'Has the longest coastline of any country.'),
  (5, 'China',           9597000, 'https://en.wikipedia.org/wiki/China', 1, 'Borders more countries than almost any other nation.'),
  (5, 'Brazil',          8516000, 'https://en.wikipedia.org/wiki/Brazil', 1, 'The largest country in South America.'),
  (5, 'Australia',       7692000, 'https://en.wikipedia.org/wiki/Australia', 1, 'The only country that is also a continent.'),
  (5, 'India',           3287000, 'https://en.wikipedia.org/wiki/India', 1, 'The most populous country in the world.'),
  (5, 'Argentina',       2780000, 'https://en.wikipedia.org/wiki/Argentina', 2, 'The second-largest country in South America.'),
  (5, 'Kazakhstan',      2725000, 'https://en.wikipedia.org/wiki/Kazakhstan', 2, 'The largest landlocked country in the world.'),
  (5, 'Algeria',         2382000, 'https://en.wikipedia.org/wiki/Algeria', 2, 'The largest country in Africa by area.'),
  (5, 'Saudi Arabia',    2150000, 'https://en.wikipedia.org/wiki/Saudi_Arabia', 2, 'The largest country on the Arabian Peninsula.'),
  (5, 'Mexico',          1964000, 'https://en.wikipedia.org/wiki/Mexico', 1, 'The largest Spanish-speaking country by area.'),
  (5, 'Indonesia',       1905000, 'https://en.wikipedia.org/wiki/Indonesia', 2, 'The world''s largest island country.'),
  (5, 'Iran',            1648000, 'https://en.wikipedia.org/wiki/Iran', 2, 'The second-largest country in the Middle East.'),
  (5, 'Peru',            1285000, 'https://en.wikipedia.org/wiki/Peru', 2, 'Home to a large stretch of the Amazon rainforest.'),
  (5, 'Egypt',           1002000, 'https://en.wikipedia.org/wiki/Egypt', 1, 'Nearly all of its population lives along the Nile.'),
  (5, 'France',           551000, 'https://en.wikipedia.org/wiki/France', 1, 'The largest country in the European Union by area.'),
  (5, 'Spain',            506000, 'https://en.wikipedia.org/wiki/Spain', 1, 'The second-largest country in Western Europe.'),
  (5, 'Japan',             378000, 'https://en.wikipedia.org/wiki/Japan', 1, 'An island nation made up of nearly 7,000 islands.')
on conflict (list_id, label) do nothing;

-- 6. Famous films by release year
insert into public.list_items (list_id, label, value, source_url, familiarity, fact) values
  (6, 'The Kid',                 1921, 'https://en.wikipedia.org/wiki/The_Kid_(1921_film)', 2, 'A Charlie Chaplin silent comedy-drama.'),
  (6, 'Metropolis',              1927, 'https://en.wikipedia.org/wiki/Metropolis_(1927_film)', 2, 'A landmark German expressionist science-fiction film.'),
  (6, 'King Kong',               1933, 'https://en.wikipedia.org/wiki/King_Kong_(1933_film)', 2, 'A giant ape is brought from a remote island to New York.'),
  (6, 'Gone with the Wind',      1939, 'https://en.wikipedia.org/wiki/Gone_with_the_Wind_(film)', 1, 'An epic Civil War-era romance set in the American South.'),
  (6, 'Casablanca',              1942, 'https://en.wikipedia.org/wiki/Casablanca_(film)', 1, 'A wartime romance set in French Morocco.'),
  (6, 'It''s a Wonderful Life',  1946, 'https://en.wikipedia.org/wiki/It%27s_a_Wonderful_Life', 2, 'A Christmas classic about a man shown life without him.'),
  (6, 'Singin'' in the Rain',    1952, 'https://en.wikipedia.org/wiki/Singin%27_in_the_Rain', 2, 'A musical comedy about Hollywood''s switch to sound.'),
  (6, 'Psycho',                  1960, 'https://en.wikipedia.org/wiki/Psycho_(1960_film)', 1, 'Alfred Hitchcock''s landmark horror-thriller.'),
  (6, 'The Sound of Music',      1965, 'https://en.wikipedia.org/wiki/The_Sound_of_Music_(film)', 1, 'A musical about a governess and the von Trapp family.'),
  (6, '2001: A Space Odyssey',   1968, 'https://en.wikipedia.org/wiki/2001:_A_Space_Odyssey_(film)', 2, 'Stanley Kubrick''s landmark science-fiction epic.'),
  (6, 'The Godfather',           1972, 'https://en.wikipedia.org/wiki/The_Godfather', 1, 'A saga of a fictional Italian-American crime family.'),
  (6, 'Jaws',                    1975, 'https://en.wikipedia.org/wiki/Jaws_(film)', 1, 'A great white shark terrorizes a New England beach town.'),
  (6, 'Star Wars',               1977, 'https://en.wikipedia.org/wiki/Star_Wars_(film)', 1, 'The film that launched the Star Wars saga.'),
  (6, 'E.T. the Extra-Terrestrial', 1982, 'https://en.wikipedia.org/wiki/E.T._the_Extra-Terrestrial', 1, 'A boy befriends a stranded alien.'),
  (6, 'Back to the Future',      1985, 'https://en.wikipedia.org/wiki/Back_to_the_Future', 1, 'A teenager travels back in time in a DeLorean.'),
  (6, 'Jurassic Park',           1993, 'https://en.wikipedia.org/wiki/Jurassic_Park_(film)', 1, 'Dinosaurs are cloned for a theme park that goes wrong.'),
  (6, 'Titanic',                 1997, 'https://en.wikipedia.org/wiki/Titanic_(1997_film)', 1, 'A romance set aboard the doomed ocean liner.'),
  (6, 'The Matrix',              1999, 'https://en.wikipedia.org/wiki/The_Matrix', 1, 'A hacker learns reality is a simulation.'),
  (6, 'Fellowship of the Ring',  2001, 'https://en.wikipedia.org/wiki/The_Lord_of_the_Rings:_The_Fellowship_of_the_Ring', 1, 'The first film in Peter Jackson''s Lord of the Rings trilogy.'),
  (6, 'Avatar',                  2009, 'https://en.wikipedia.org/wiki/Avatar_(2009_film)', 1, 'A marine on an alien moon joins the native Na''vi.'),
  (6, 'Frozen',                  2013, 'https://en.wikipedia.org/wiki/Frozen_(2013_film)', 1, 'An animated musical about two royal sisters.')
on conflict (list_id, label) do nothing;

-- 7. Rivers by length (km)
insert into public.list_items (list_id, label, value, source_url, familiarity, fact) values
  (7, 'Nile',          6650, 'https://en.wikipedia.org/wiki/Nile', 1, 'Widely cited as the longest river in the world.'),
  (7, 'Amazon',        6400, 'https://en.wikipedia.org/wiki/Amazon_River', 1, 'Carries more water than any other river on Earth.'),
  (7, 'Yangtze',       6300, 'https://en.wikipedia.org/wiki/Yangtze', 2, 'The longest river in Asia, flowing entirely within China.'),
  (7, 'Yellow River',  5464, 'https://en.wikipedia.org/wiki/Yellow_River', 2, 'Known as the "Cradle of Chinese Civilization".'),
  (7, 'Congo',         4700, 'https://en.wikipedia.org/wiki/Congo_River', 2, 'The deepest river in the world.'),
  (7, 'Niger',         4180, 'https://en.wikipedia.org/wiki/Niger_River', 3, 'The principal river of West Africa.'),
  (7, 'Mississippi',   3730, 'https://en.wikipedia.org/wiki/Mississippi_River', 1, 'The second-longest river system in North America.'),
  (7, 'Ob',            3650, 'https://en.wikipedia.org/wiki/Ob_River', 3, 'A major Siberian river flowing into the Arctic Ocean.'),
  (7, 'Yenisei',       3487, 'https://en.wikipedia.org/wiki/Yenisei_River', 3, 'Carries the most water of any river flowing into the Arctic.'),
  (7, 'Volga',         3531, 'https://en.wikipedia.org/wiki/Volga_River', 2, 'The longest river in Europe.'),
  (7, 'Rio Grande',    3051, 'https://en.wikipedia.org/wiki/Rio_Grande', 2, 'Forms much of the border between the US and Mexico.'),
  (7, 'Danube',        2850, 'https://en.wikipedia.org/wiki/Danube', 1, 'Flows through more countries than any other river.'),
  (7, 'Zambezi',       2574, 'https://en.wikipedia.org/wiki/Zambezi', 2, 'Plunges over Victoria Falls on the Zambia-Zimbabwe border.'),
  (7, 'Colorado River', 2334, 'https://en.wikipedia.org/wiki/Colorado_River', 2, 'Carved the Grand Canyon over millions of years.'),
  (7, 'Rhine',          1233, 'https://en.wikipedia.org/wiki/Rhine', 1, 'One of the busiest commercial waterways in Europe.'),
  (7, 'Seine',           777, 'https://en.wikipedia.org/wiki/Seine', 1, 'Flows through the heart of Paris.'),
  (7, 'Thames',           346, 'https://en.wikipedia.org/wiki/River_Thames', 1, 'Flows through London past the Houses of Parliament.'),
  (7, 'Jordan River',     251, 'https://en.wikipedia.org/wiki/Jordan_River', 2, 'A river of major religious significance in the Middle East.')
on conflict (list_id, label) do nothing;

-- 8. Chemical elements by atomic number
insert into public.list_items (list_id, label, value, source_url, familiarity, fact) values
  (8, 'Hydrogen',   1,  'https://en.wikipedia.org/wiki/Hydrogen', 1, 'The lightest and most abundant element in the universe.'),
  (8, 'Helium',     2,  'https://en.wikipedia.org/wiki/Helium', 1, 'A noble gas used to fill balloons and airships.'),
  (8, 'Carbon',     6,  'https://en.wikipedia.org/wiki/Carbon', 1, 'The basis of all known organic life.'),
  (8, 'Oxygen',     8,  'https://en.wikipedia.org/wiki/Oxygen', 1, 'Makes up about 21% of Earth''s atmosphere.'),
  (8, 'Neon',       10, 'https://en.wikipedia.org/wiki/Neon', 2, 'Famous for its use in glowing signs.'),
  (8, 'Sodium',     11, 'https://en.wikipedia.org/wiki/Sodium', 1, 'A soft, reactive metal found in table salt.'),
  (8, 'Aluminium',  13, 'https://en.wikipedia.org/wiki/Aluminium', 1, 'The most abundant metal in Earth''s crust.'),
  (8, 'Phosphorus', 15, 'https://en.wikipedia.org/wiki/Phosphorus', 2, 'Essential to DNA and glows faintly in the dark.'),
  (8, 'Chlorine',   17, 'https://en.wikipedia.org/wiki/Chlorine', 2, 'A greenish-yellow gas used to disinfect water.'),
  (8, 'Potassium',  19, 'https://en.wikipedia.org/wiki/Potassium', 2, 'A soft metal essential to nerve and muscle function.'),
  (8, 'Titanium',   22, 'https://en.wikipedia.org/wiki/Titanium', 2, 'Prized for its strength-to-weight ratio.'),
  (8, 'Iron',       26, 'https://en.wikipedia.org/wiki/Iron', 1, 'The main component of Earth''s core.'),
  (8, 'Copper',     29, 'https://en.wikipedia.org/wiki/Copper', 1, 'One of the first metals used by humans.'),
  (8, 'Krypton',    36, 'https://en.wikipedia.org/wiki/Krypton', 2, 'A noble gas used in some photographic flashes.'),
  (8, 'Zirconium',  40, 'https://en.wikipedia.org/wiki/Zirconium', 3, 'Highly resistant to corrosion, used in nuclear reactors.'),
  (8, 'Iodine',     53, 'https://en.wikipedia.org/wiki/Iodine', 2, 'Essential for thyroid hormone production.'),
  (8, 'Tungsten',   74, 'https://en.wikipedia.org/wiki/Tungsten', 2, 'Has the highest melting point of any metal.'),
  (8, 'Gold',       79, 'https://en.wikipedia.org/wiki/Gold', 1, 'A dense, prized metal that rarely corrodes.'),
  (8, 'Radon',      86, 'https://en.wikipedia.org/wiki/Radon', 2, 'A radioactive noble gas that can accumulate in basements.'),
  (8, 'Uranium',    92, 'https://en.wikipedia.org/wiki/Uranium', 1, 'The heaviest naturally occurring element used as fuel.')
on conflict (list_id, label) do nothing;

-- 9. Famous novels by year of first publication
insert into public.list_items (list_id, label, value, source_url, familiarity, fact) values
  (9, 'Don Quixote',              1605, 'https://en.wikipedia.org/wiki/Don_Quixote', 2, 'Often called the first modern novel.'),
  (9, 'Robinson Crusoe',          1719, 'https://en.wikipedia.org/wiki/Robinson_Crusoe', 2, 'A castaway survives alone on a remote island.'),
  (9, 'Gulliver''s Travels',      1726, 'https://en.wikipedia.org/wiki/Gulliver%27s_Travels', 2, 'A satirical account of voyages to strange lands.'),
  (9, 'Pride and Prejudice',      1813, 'https://en.wikipedia.org/wiki/Pride_and_Prejudice', 1, 'Jane Austen''s novel of manners and marriage.'),
  (9, 'Frankenstein',             1818, 'https://en.wikipedia.org/wiki/Frankenstein', 1, 'Mary Shelley''s tale of a scientist and his creation.'),
  (9, 'Oliver Twist',             1838, 'https://en.wikipedia.org/wiki/Oliver_Twist', 2, 'Charles Dickens''s novel about an orphan in London.'),
  (9, 'Wuthering Heights',        1847, 'https://en.wikipedia.org/wiki/Wuthering_Heights', 2, 'Emily Bronte''s only novel, set on the Yorkshire moors.'),
  (9, 'Moby-Dick',                1851, 'https://en.wikipedia.org/wiki/Moby-Dick', 2, 'Herman Melville''s epic of a whaling voyage.'),
  (9, 'Alice in Wonderland',      1865, 'https://en.wikipedia.org/wiki/Alice%27s_Adventures_in_Wonderland', 1, 'Lewis Carroll''s tale of a girl who falls down a rabbit hole.'),
  (9, 'War and Peace',            1869, 'https://en.wikipedia.org/wiki/War_and_Peace', 1, 'Leo Tolstoy''s sprawling novel set during the Napoleonic Wars.'),
  (9, 'Anna Karenina',            1878, 'https://en.wikipedia.org/wiki/Anna_Karenina', 2, 'Leo Tolstoy''s tragedy of love and Russian society.'),
  (9, 'Dracula',                  1897, 'https://en.wikipedia.org/wiki/Dracula', 1, 'Bram Stoker''s gothic novel that defined the vampire genre.'),
  (9, 'The Great Gatsby',         1925, 'https://en.wikipedia.org/wiki/The_Great_Gatsby', 1, 'F. Scott Fitzgerald''s novel of the Jazz Age.'),
  (9, 'Brave New World',          1932, 'https://en.wikipedia.org/wiki/Brave_New_World', 1, 'Aldous Huxley''s dystopian vision of the future.'),
  (9, 'The Hobbit',               1937, 'https://en.wikipedia.org/wiki/The_Hobbit', 1, 'J.R.R. Tolkien''s prelude to The Lord of the Rings.'),
  (9, 'Nineteen Eighty-Four',     1949, 'https://en.wikipedia.org/wiki/Nineteen_Eighty-Four', 1, 'George Orwell''s dystopian novel of surveillance and control.'),
  (9, 'Lord of the Flies',        1954, 'https://en.wikipedia.org/wiki/Lord_of_the_Flies', 1, 'William Golding''s novel of boys stranded on an island.'),
  (9, 'To Kill a Mockingbird',    1960, 'https://en.wikipedia.org/wiki/To_Kill_a_Mockingbird', 1, 'Harper Lee''s novel of racial injustice in the American South.'),
  (9, 'One Hundred Years of Solitude', 1967, 'https://en.wikipedia.org/wiki/One_Hundred_Years_of_Solitude', 2, 'Gabriel Garcia Marquez''s landmark of magical realism.'),
  (9, 'Harry Potter',             1997, 'https://en.wikipedia.org/wiki/Harry_Potter_and_the_Philosopher%27s_Stone', 1, 'J.K. Rowling''s first novel about a young wizard.')
on conflict (list_id, label) do nothing;

-- 10. Summer Olympic host cities by year (first hosting only)
insert into public.list_items (list_id, label, value, source_url, familiarity, fact) values
  (10, 'Athens',      1896, 'https://en.wikipedia.org/wiki/1896_Summer_Olympics', 1, 'Host of the first modern Olympic Games.'),
  (10, 'Paris',       1900, 'https://en.wikipedia.org/wiki/1900_Summer_Olympics', 1, 'The second modern Olympics, held alongside a World''s Fair.'),
  (10, 'St. Louis',   1904, 'https://en.wikipedia.org/wiki/1904_Summer_Olympics', 2, 'The first Olympics held outside Europe.'),
  (10, 'London',      1908, 'https://en.wikipedia.org/wiki/1908_Summer_Olympics', 1, 'Stepped in as host after Rome withdrew.'),
  (10, 'Stockholm',   1912, 'https://en.wikipedia.org/wiki/1912_Summer_Olympics', 2, 'The last Games before a 12-year hiatus caused by World War I.'),
  (10, 'Antwerp',     1920, 'https://en.wikipedia.org/wiki/1920_Summer_Olympics', 2, 'The first Games after World War I.'),
  (10, 'Amsterdam',   1928, 'https://en.wikipedia.org/wiki/1928_Summer_Olympics', 2, 'The first Games with a permanent Olympic flame.'),
  (10, 'Los Angeles', 1932, 'https://en.wikipedia.org/wiki/1932_Summer_Olympics', 1, 'Held during the Great Depression.'),
  (10, 'Berlin',      1936, 'https://en.wikipedia.org/wiki/1936_Summer_Olympics', 1, 'Notable for Jesse Owens winning four gold medals.'),
  (10, 'Helsinki',    1952, 'https://en.wikipedia.org/wiki/1952_Summer_Olympics', 2, 'The first Games with the Soviet Union competing.'),
  (10, 'Melbourne',   1956, 'https://en.wikipedia.org/wiki/1956_Summer_Olympics', 2, 'The first Games held in the Southern Hemisphere.'),
  (10, 'Rome',        1960, 'https://en.wikipedia.org/wiki/1960_Summer_Olympics', 1, 'The first Games broadcast live on television across Europe.'),
  (10, 'Tokyo',       1964, 'https://en.wikipedia.org/wiki/1964_Summer_Olympics', 1, 'The first Olympics held in Asia.'),
  (10, 'Mexico City', 1968, 'https://en.wikipedia.org/wiki/1968_Summer_Olympics', 1, 'The first Games held in Latin America.'),
  (10, 'Munich',      1972, 'https://en.wikipedia.org/wiki/1972_Summer_Olympics', 2, 'Remembered for the hostage crisis and Mark Spitz''s seven golds.'),
  (10, 'Montreal',    1976, 'https://en.wikipedia.org/wiki/1976_Summer_Olympics', 2, 'Nadia Comaneci scored gymnastics'' first perfect 10 here.'),
  (10, 'Moscow',      1980, 'https://en.wikipedia.org/wiki/1980_Summer_Olympics', 2, 'Boycotted by dozens of countries including the United States.'),
  (10, 'Seoul',       1988, 'https://en.wikipedia.org/wiki/1988_Summer_Olympics', 1, 'Marked South Korea''s emergence on the world stage.'),
  (10, 'Barcelona',   1992, 'https://en.wikipedia.org/wiki/1992_Summer_Olympics', 1, 'Featured the US "Dream Team" basketball squad.'),
  (10, 'Atlanta',     1996, 'https://en.wikipedia.org/wiki/1996_Summer_Olympics', 1, 'Held to mark the 100th anniversary of the modern Games.'),
  (10, 'Sydney',      2000, 'https://en.wikipedia.org/wiki/2000_Summer_Olympics', 1, 'Widely praised as one of the best-organized Games.'),
  (10, 'Beijing',     2008, 'https://en.wikipedia.org/wiki/2008_Summer_Olympics', 1, 'Featured the "Bird''s Nest" stadium and Michael Phelps''s eight golds.')
on conflict (list_id, label) do nothing;

-- 11. Animals by typical adult top speed (km/h)
insert into public.list_items (list_id, label, value, source_url, familiarity, fact) values
  (11, 'Peregrine falcon',    389, 'https://en.wikipedia.org/wiki/Peregrine_falcon', 1, 'The fastest animal on Earth in a hunting dive.'),
  (11, 'Cheetah',             120, 'https://en.wikipedia.org/wiki/Cheetah', 1, 'The fastest land animal over short distances.'),
  (11, 'Pronghorn',            88, 'https://en.wikipedia.org/wiki/Pronghorn', 3, 'North America''s fastest land animal, built for endurance.'),
  (11, 'Lion',                 80, 'https://en.wikipedia.org/wiki/Lion', 1, 'Can sprint in short bursts while hunting.'),
  (11, 'Greyhound',            74, 'https://en.wikipedia.org/wiki/Greyhound', 2, 'A dog breed bred for centuries for its speed.'),
  (11, 'Ostrich',              70, 'https://en.wikipedia.org/wiki/Common_ostrich', 1, 'The fastest-running bird, though flightless.'),
  (11, 'Giraffe',              60, 'https://en.wikipedia.org/wiki/Giraffe', 1, 'Surprisingly fast despite its long legs and neck.'),
  (11, 'European hare',        56, 'https://en.wikipedia.org/wiki/European_hare', 2, 'Relies on speed and sharp turns to outrun predators.'),
  (11, 'Domestic cat',         48, 'https://en.wikipedia.org/wiki/Cat', 1, 'Can outrun most humans in a short sprint.'),
  (11, 'Human',                44, 'https://en.wikipedia.org/wiki/Usain_Bolt', 1, 'Usain Bolt''s recorded top speed during his 100m world record.'),
  (11, 'Elephant',             40, 'https://en.wikipedia.org/wiki/African_bush_elephant', 2, 'Can move surprisingly fast despite its huge size.'),
  (11, 'Blue whale',           30, 'https://en.wikipedia.org/wiki/Blue_whale', 2, 'Can reach short bursts of speed despite its enormous size.'),
  (11, 'Squirrel',             20, 'https://en.wikipedia.org/wiki/Squirrel', 2, 'Quick enough to escape most backyard predators.'),
  (11, 'Domestic pig',         17, 'https://en.wikipedia.org/wiki/Pig', 2, 'Faster on its feet than most people expect.'),
  (11, 'Chicken',              14, 'https://en.wikipedia.org/wiki/Chicken', 2, 'Can run in short bursts despite being flightless.'),
  (11, 'Galapagos tortoise', 0.3, 'https://en.wikipedia.org/wiki/Galapagos_tortoise', 2, 'One of the slowest-moving animals on land.'),
  (11, 'Sloth',              0.24, 'https://en.wikipedia.org/wiki/Sloth', 2, 'Moves so slowly that algae grows on its fur.'),
  (11, 'Snail',              0.05, 'https://en.wikipedia.org/wiki/Snail', 1, 'A byword for slowness, moving on a muscular foot.')
on conflict (list_id, label) do nothing;

-- 12. US states by year of admission to the Union
insert into public.list_items (list_id, label, value, source_url, familiarity, fact) values
  (12, 'Delaware',      1787, 'https://en.wikipedia.org/wiki/Delaware', 2, 'The first state to ratify the US Constitution.'),
  (12, 'Vermont',       1791, 'https://en.wikipedia.org/wiki/Vermont', 2, 'The first state admitted after the original thirteen.'),
  (12, 'Tennessee',     1796, 'https://en.wikipedia.org/wiki/Tennessee', 2, 'Known as the "Volunteer State".'),
  (12, 'Ohio',          1803, 'https://en.wikipedia.org/wiki/Ohio', 2, 'The first state carved from the Northwest Territory.'),
  (12, 'Louisiana',     1812, 'https://en.wikipedia.org/wiki/Louisiana', 2, 'Formed from part of the Louisiana Purchase.'),
  (12, 'Indiana',       1816, 'https://en.wikipedia.org/wiki/Indiana', 2, 'Its name means "Land of the Indians".'),
  (12, 'Illinois',      1818, 'https://en.wikipedia.org/wiki/Illinois', 2, 'Home to Chicago, its largest city.'),
  (12, 'Texas',         1845, 'https://en.wikipedia.org/wiki/Texas', 1, 'Was an independent republic before joining the Union.'),
  (12, 'Iowa',          1846, 'https://en.wikipedia.org/wiki/Iowa', 2, 'Known for its role in presidential primaries.'),
  (12, 'Wisconsin',     1848, 'https://en.wikipedia.org/wiki/Wisconsin', 2, 'Nicknamed "America''s Dairyland".'),
  (12, 'California',    1850, 'https://en.wikipedia.org/wiki/California', 1, 'Joined the Union shortly after the Gold Rush began.'),
  (12, 'Minnesota',     1858, 'https://en.wikipedia.org/wiki/Minnesota', 2, 'Known as the "Land of 10,000 Lakes".'),
  (12, 'Kansas',        1861, 'https://en.wikipedia.org/wiki/Kansas', 2, 'Admitted as a free state just before the Civil War.'),
  (12, 'Nevada',        1864, 'https://en.wikipedia.org/wiki/Nevada', 2, 'Admitted during the Civil War, partly for its silver wealth.'),
  (12, 'Colorado',      1876, 'https://en.wikipedia.org/wiki/Colorado', 2, 'Nicknamed the "Centennial State".'),
  (12, 'North Dakota',  1889, 'https://en.wikipedia.org/wiki/North_Dakota', 2, 'Admitted the same day as South Dakota.'),
  (12, 'Idaho',         1890, 'https://en.wikipedia.org/wiki/Idaho', 2, 'Known for its potato farming.'),
  (12, 'Utah',          1896, 'https://en.wikipedia.org/wiki/Utah', 2, 'Home to the Great Salt Lake.'),
  (12, 'Oklahoma',      1907, 'https://en.wikipedia.org/wiki/Oklahoma', 2, 'Formed from Indian and Oklahoma Territories.'),
  (12, 'Arizona',       1912, 'https://en.wikipedia.org/wiki/Arizona', 2, 'The last of the contiguous states to be admitted.'),
  (12, 'Alaska',        1959, 'https://en.wikipedia.org/wiki/Alaska', 1, 'The largest US state by area, admitted in 1959.')
on conflict (list_id, label) do nothing;

select setval('public.lists_id_seq', (select max(id) from public.lists));

commit;
