#!/usr/bin/env python3
"""Generate Ember's preloaded food database.

Emits Sources/EmberCore/Resources/preloaded-foods.json — a flat list of common foods
with approximate macros for one common serving. Values are rounded reference figures
(USDA / common labels) meant as a friction-reducing starting set, not lab-precise data;
the coach can correct, and users save their own custom items on top.

Run from the repo root:  python3 Tools/gen_foods.py
"""
import json
import os
import re

# (name, serving description, kcal, protein g, carb g, fat g) — per serving shown.
FOODS = [
    # Poultry, meat, fish
    ("Chicken breast, cooked", "100 g", 165, 31, 0, 3.6),
    ("Chicken thigh, cooked", "100 g", 209, 26, 0, 10.9),
    ("Ground chicken, cooked", "100 g", 189, 25, 0, 9),
    ("Ground beef, 85/15, cooked", "100 g", 250, 26, 0, 15),
    ("Ground beef, 90/10, cooked", "100 g", 217, 26, 0, 11.8),
    ("Sirloin steak, cooked", "100 g", 206, 28, 0, 10),
    ("Pork chop, cooked", "100 g", 231, 26, 0, 14),
    ("Ground turkey, 93/7, cooked", "100 g", 176, 22, 0, 9),
    ("Turkey breast, deli", "2 slices (56 g)", 50, 10, 1, 0.5),
    ("Ham, deli", "2 slices (56 g)", 60, 9, 1.5, 2),
    ("Bacon, cooked", "2 slices (16 g)", 87, 6, 0.2, 6.7),
    ("Sausage link, cooked", "1 link (45 g)", 140, 8, 1, 12),
    ("Salmon, cooked", "100 g", 206, 22, 0, 12),
    ("Tuna, canned in water", "1 can drained (142 g)", 142, 33, 0, 1),
    ("Shrimp, cooked", "100 g", 99, 24, 0.2, 0.3),
    ("Cod, cooked", "100 g", 105, 23, 0, 0.9),
    ("Tilapia, cooked", "100 g", 128, 26, 0, 2.7),

    # Eggs & dairy
    ("Egg, large", "1 large (50 g)", 72, 6.3, 0.4, 4.8),
    ("Egg white, large", "1 (33 g)", 17, 3.6, 0.2, 0.1),
    ("Greek yogurt, nonfat plain", "170 g", 100, 17, 6, 0.7),
    ("Greek yogurt, 2% plain", "170 g", 150, 20, 8, 4),
    ("Cottage cheese, low-fat", "1/2 cup (113 g)", 90, 12, 5, 2.5),
    ("Whole milk", "1 cup (244 g)", 149, 8, 12, 8),
    ("2% milk", "1 cup (244 g)", 122, 8, 12, 5),
    ("Skim milk", "1 cup (245 g)", 83, 8, 12, 0.2),
    ("Almond milk, unsweetened", "1 cup (240 g)", 30, 1, 1, 2.5),
    ("Cheddar cheese", "1 oz (28 g)", 115, 7, 0.4, 9.5),
    ("Mozzarella, part-skim", "1 oz (28 g)", 72, 7, 1, 4.5),
    ("Parmesan, grated", "1 tbsp (5 g)", 22, 2, 0.2, 1.4),
    ("String cheese", "1 stick (28 g)", 80, 7, 1, 6),
    ("Butter", "1 tbsp (14 g)", 102, 0.1, 0, 11.5),
    ("Cream cheese", "1 tbsp (14 g)", 51, 1, 0.8, 5),

    # Grains & starches
    ("White rice, cooked", "1 cup (158 g)", 205, 4.3, 45, 0.4),
    ("Brown rice, cooked", "1 cup (195 g)", 216, 5, 45, 1.8),
    ("Quinoa, cooked", "1 cup (185 g)", 222, 8, 39, 3.6),
    ("Oats, dry", "1/2 cup (40 g)", 150, 5, 27, 3),
    ("Pasta, cooked", "1 cup (140 g)", 220, 8, 43, 1.3),
    ("Couscous, cooked", "1 cup (157 g)", 176, 6, 36, 0.3),
    ("Whole wheat bread", "1 slice (28 g)", 69, 3.6, 12, 1),
    ("White bread", "1 slice (25 g)", 66, 2, 13, 0.8),
    ("Bagel, plain", "1 medium (95 g)", 245, 10, 48, 1.5),
    ("English muffin", "1 (57 g)", 134, 4.4, 26, 1),
    ("Flour tortilla", "1 medium (45 g)", 140, 4, 23, 3.5),
    ("Corn flakes cereal", "1 cup (28 g)", 100, 2, 24, 0.1),
    ("Rice cake", "1 (9 g)", 35, 0.7, 7.3, 0.3),
    ("Saltine crackers", "5 (15 g)", 62, 1.3, 11, 1.4),
    ("Pancakes", "2 (77 g)", 175, 5, 22, 7),
    ("Baked potato", "1 medium (173 g)", 161, 4.3, 37, 0.2),
    ("Sweet potato, baked", "1 medium (151 g)", 112, 2, 26, 0.1),
    ("Hash browns", "1 cup (156 g)", 207, 2, 22, 12),
    ("Corn", "1 cup (154 g)", 132, 5, 29, 1.8),

    # Legumes, nuts, seeds, spreads
    ("Black beans, cooked", "1/2 cup (86 g)", 114, 7.6, 20, 0.5),
    ("Chickpeas, cooked", "1/2 cup (82 g)", 134, 7, 22, 2),
    ("Lentils, cooked", "1/2 cup (99 g)", 115, 9, 20, 0.4),
    ("Kidney beans, cooked", "1/2 cup (89 g)", 112, 7.7, 20, 0.4),
    ("Edamame", "1/2 cup (78 g)", 94, 9, 7, 4),
    ("Tofu, firm", "100 g", 144, 15, 3.5, 8.7),
    ("Green peas", "1 cup (145 g)", 117, 8, 21, 0.6),
    ("Hummus", "2 tbsp (30 g)", 70, 2, 6, 5),
    ("Peanut butter", "2 tbsp (32 g)", 188, 8, 6, 16),
    ("Almond butter", "2 tbsp (32 g)", 196, 7, 6, 18),
    ("Almonds", "1 oz (28 g)", 164, 6, 6, 14),
    ("Walnuts", "1 oz (28 g)", 185, 4.3, 4, 18.5),
    ("Cashews", "1 oz (28 g)", 157, 5, 9, 12),
    ("Peanuts", "1 oz (28 g)", 161, 7, 4.6, 14),
    ("Pistachios", "1 oz (28 g)", 159, 6, 8, 13),
    ("Sunflower seeds", "1 oz (28 g)", 165, 5.5, 7, 14),
    ("Pumpkin seeds", "1 oz (28 g)", 151, 7, 5, 13),
    ("Chia seeds", "1 tbsp (12 g)", 58, 2, 5, 3.7),
    ("Ground flaxseed", "1 tbsp (7 g)", 37, 1.3, 2, 3),

    # Fruit
    ("Banana", "1 medium (118 g)", 105, 1.3, 27, 0.4),
    ("Apple", "1 medium (182 g)", 95, 0.5, 25, 0.3),
    ("Orange", "1 medium (131 g)", 62, 1.2, 15, 0.2),
    ("Grapefruit", "1/2 medium (123 g)", 52, 1, 13, 0.2),
    ("Pear", "1 medium (178 g)", 101, 0.6, 27, 0.2),
    ("Peach", "1 medium (150 g)", 59, 1.4, 14, 0.4),
    ("Strawberries", "1 cup (152 g)", 49, 1, 12, 0.5),
    ("Blueberries", "1 cup (148 g)", 84, 1.1, 21, 0.5),
    ("Raspberries", "1 cup (123 g)", 64, 1.5, 15, 0.8),
    ("Grapes", "1 cup (151 g)", 104, 1.1, 27, 0.2),
    ("Cherries", "1 cup (154 g)", 97, 1.6, 25, 0.3),
    ("Watermelon", "1 cup (152 g)", 46, 0.9, 12, 0.2),
    ("Cantaloupe", "1 cup (160 g)", 54, 1.3, 13, 0.3),
    ("Pineapple", "1 cup (165 g)", 82, 0.9, 22, 0.2),
    ("Mango", "1 cup (165 g)", 99, 1.4, 25, 0.6),
    ("Avocado", "1/2 medium (100 g)", 160, 2, 9, 15),

    # Vegetables
    ("Broccoli, cooked", "1 cup (156 g)", 55, 3.7, 11, 0.6),
    ("Cauliflower", "1 cup (107 g)", 27, 2, 5, 0.3),
    ("Spinach, raw", "1 cup (30 g)", 7, 0.9, 1.1, 0.1),
    ("Kale, raw", "1 cup (21 g)", 7, 0.6, 1.4, 0.1),
    ("Romaine lettuce", "1 cup (47 g)", 8, 0.6, 1.5, 0.1),
    ("Carrot", "1 medium (61 g)", 25, 0.6, 6, 0.1),
    ("Bell pepper", "1 medium (119 g)", 31, 1, 7, 0.3),
    ("Cucumber", "1 cup (104 g)", 16, 0.7, 3.8, 0.1),
    ("Tomato", "1 medium (123 g)", 22, 1.1, 4.8, 0.2),
    ("Green beans", "1 cup (100 g)", 31, 1.8, 7, 0.2),
    ("Mushrooms", "1 cup (70 g)", 15, 2.2, 2.3, 0.2),
    ("Onion", "1/2 cup (80 g)", 32, 0.9, 7.5, 0.1),
    ("Zucchini", "1 cup (124 g)", 21, 1.5, 3.9, 0.4),
    ("Asparagus", "1 cup (134 g)", 27, 3, 5, 0.2),
    ("Brussels sprouts", "1 cup (88 g)", 38, 3, 8, 0.3),
    ("Beets", "1 cup (136 g)", 58, 2.2, 13, 0.2),

    # Fats & oils
    ("Olive oil", "1 tbsp (14 g)", 119, 0, 0, 14),
    ("Coconut oil", "1 tbsp (14 g)", 117, 0, 0, 14),
    ("Mayonnaise", "1 tbsp (14 g)", 94, 0.1, 0.1, 10),
    ("Ranch dressing", "2 tbsp (30 g)", 130, 0.5, 2, 13.5),

    # Beverages
    ("Orange juice", "1 cup (248 g)", 112, 1.7, 26, 0.5),
    ("Coffee, black", "1 cup (240 g)", 2, 0.3, 0, 0),
    ("Cola", "12 oz (368 g)", 140, 0, 39, 0),
    ("Sports drink", "20 oz (591 g)", 130, 0, 34, 0),
    ("Beer", "12 oz (355 g)", 153, 1.6, 13, 0),
    ("Red wine", "5 oz (147 g)", 125, 0.1, 4, 0),

    # Protein supplements
    ("Whey protein powder", "1 scoop (31 g)", 120, 24, 3, 1.5),
    ("Protein shake, ready-to-drink", "1 bottle (330 mL)", 160, 30, 5, 2.5),
    ("Protein bar", "1 bar (60 g)", 220, 20, 22, 7),

    # Snacks & sweets
    ("Dark chocolate", "1 oz (28 g)", 170, 2, 13, 12),
    ("Potato chips", "1 oz (28 g)", 152, 2, 15, 10),
    ("Pretzels", "1 oz (28 g)", 108, 2.6, 23, 0.8),
    ("Popcorn, air-popped", "3 cups (24 g)", 93, 3, 19, 1),
    ("Granola bar", "1 bar (40 g)", 190, 4, 29, 7),
    ("Trail mix", "1 oz (28 g)", 137, 4, 13, 9),
    ("Vanilla ice cream", "1/2 cup (66 g)", 137, 2.3, 16, 7),

    # Common dishes / fast food
    ("Cheeseburger, fast food", "1 burger", 300, 15, 33, 12),
    ("Cheese pizza", "1 slice (107 g)", 285, 12, 36, 10),
    ("French fries", "medium (117 g)", 365, 4, 48, 17),
    ("Bean & cheese burrito", "1 burrito", 380, 14, 55, 12),
    ("California roll", "6 pieces", 255, 9, 38, 7),
    ("Instant ramen", "1 pack", 380, 8, 52, 14),
    ("Mac and cheese", "1 cup (200 g)", 310, 13, 32, 14),
    ("Chicken Caesar wrap", "1 wrap", 430, 25, 35, 22),
    ("PB&J sandwich", "1 sandwich", 350, 12, 45, 14),

    # Condiments & sweeteners
    ("Ketchup", "1 tbsp (17 g)", 17, 0.2, 4.5, 0),
    ("Mustard", "1 tsp (5 g)", 3, 0.2, 0.3, 0.2),
    ("Soy sauce", "1 tbsp (16 g)", 8, 1.3, 0.8, 0),
    ("Salsa", "2 tbsp (36 g)", 10, 0.5, 2, 0.1),
    ("Honey", "1 tbsp (21 g)", 64, 0.1, 17, 0),
    ("Maple syrup", "1 tbsp (20 g)", 52, 0, 13, 0),
    ("Jam", "1 tbsp (20 g)", 56, 0.1, 14, 0),
    ("Sugar, white", "1 tsp (4 g)", 16, 0, 4.2, 0),
]


def slug(name):
    s = name.lower()
    s = re.sub(r"[^a-z0-9]+", "_", s)
    return s.strip("_")


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    out_dir = os.path.join(here, "..", "Sources", "EmberCore", "Resources")
    os.makedirs(out_dir, exist_ok=True)
    out_path = os.path.join(out_dir, "preloaded-foods.json")

    seen = set()
    records = []
    for name, serving, kcal, protein, carb, fat in FOODS:
        fid = slug(name)
        if fid in seen:
            raise SystemExit(f"duplicate id: {fid} ({name})")
        seen.add(fid)
        records.append({
            "id": fid,
            "name": name,
            "serving": serving,
            "kcal": kcal,
            "protein": protein,
            "carb": carb,
            "fat": fat,
        })

    with open(out_path, "w") as f:
        json.dump(records, f, indent=2)
        f.write("\n")
    print(f"wrote {len(records)} foods to {os.path.relpath(out_path)}")


if __name__ == "__main__":
    main()
