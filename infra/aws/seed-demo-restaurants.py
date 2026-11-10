import requests
import json
import os
import sys

BASE_URL = "http://13.207.240.55"
PIZZA_CATEGORY_ID = "6af27aa8c470cf2441eab006"
BEV_CATEGORY_ID = "6af3193b63e35914d1b1aae4"

ASSET_DIR = "/tmp/demo_assets"
TOPPING_ASSETS = "/home/satyajit/projects/mernspace-project/mernspace-c-client-ui/public"

session = requests.Session()

# 1. Login
print("Logging in...")
login_res = session.post(
    f"{BASE_URL}/api/auth/auth/login",
    json={"email": "admin@mernspace.local", "password": "Admin@12345"}
)
if login_res.status_code != 200:
    print(f"Login failed: {login_res.status_code} {login_res.text}")
    sys.exit(1)

token_res = session.get(f"{BASE_URL}/api/auth/accessToken")
token = token_res.json()["token"]
headers = {"Authorization": f"Bearer {token}"}
print("Authenticated successfully.")

# 2. Get or create tenants
tenants_res = session.get(f"{BASE_URL}/api/auth/tenants?perPage=100")
existing_tenants = {t["name"]: t["id"] for t in tenants_res.json().get("data", [])}
print("Existing tenants:", existing_tenants)

desired_tenants = [
    ("Demo Restaurant", "1 Demo Street, Tech City"),
    ("Little Italy Trattoria", "42 Napoli Way, Suite 100"),
    ("Brooklyn Pizza Yard", "78 Bedford Ave, Brooklyn, NY"),
    ("Artisan Woodfire Pizzeria", "15 Pine Grove Blvd, San Francisco, CA")
]

tenant_ids = {}
for name, addr in desired_tenants:
    if name in existing_tenants:
        tenant_ids[name] = existing_tenants[name]
        print(f"Tenant '{name}' exists with ID {existing_tenants[name]}")
    else:
        res = session.post(
            f"{BASE_URL}/api/auth/tenants",
            json={"name": name, "address": addr},
            headers=headers
        )
        if res.status_code in (200, 201):
            tid = res.json()["id"]
            tenant_ids[name] = tid
            print(f"Created tenant '{name}' with ID {tid}")
        else:
            print(f"Failed to create tenant '{name}': {res.status_code} {res.text}")

print("All tenant IDs:", tenant_ids)

# 3. Seed Toppings for each tenant
toppings_def = [
    ("Extra Mozzarella Cheese", 45, f"{TOPPING_ASSETS}/cheese.png", "image/png"),
    ("Fresh Sliced Mushrooms", 35, f"{TOPPING_ASSETS}/mushroom.png", "image/png"),
    ("Spicy Jalapenos", 30, f"{TOPPING_ASSETS}/jelapeno.png", "image/png"),
    ("Grilled Herb Chicken", 60, f"{TOPPING_ASSETS}/chicken.png", "image/png")
]

for t_name, tid in tenant_ids.items():
    existing_toppings = session.get(f"{BASE_URL}/api/catalog/toppings?tenantId={tid}").json()
    existing_top_names = {top["name"] for top in existing_toppings}
    print(f"\n--- Seeding toppings for tenant {tid} ({t_name}) ---")
    for top_name, top_price, top_path, mime in toppings_def:
        if top_name in existing_top_names:
            print(f"Topping '{top_name}' already exists for tenant {tid}")
            continue
        with open(top_path, "rb") as f:
            files = {"image": (os.path.basename(top_path), f, mime)}
            data = {"name": top_name, "price": str(top_price), "tenantId": str(tid)}
            res = session.post(f"{BASE_URL}/api/catalog/toppings", data=data, files=files, headers=headers)
            print(f"  Created topping '{top_name}': {res.status_code}")

# 4. Products definition per tenant
products_catalog = {
    "Demo Restaurant": [
        {
            "name": "Pepperoni Classic",
            "desc": "Crispy beef pepperoni, melted mozzarella & rich Italian tomato sauce",
            "prices": {"Small": 279, "Large": 449},
            "category": PIZZA_CATEGORY_ID,
            "attr": [{"name": "Crust", "value": "Thin"}],
            "img": f"{ASSET_DIR}/pepperoni.jpg",
            "mime": "image/jpeg"
        },
        {
            "name": "Farmhouse Veggie Supreme",
            "desc": "Fresh bell peppers, crisp red onions, button mushrooms, ripe tomatoes",
            "prices": {"Small": 249, "Large": 399},
            "category": PIZZA_CATEGORY_ID,
            "attr": [{"name": "Crust", "value": "Thin"}],
            "img": f"{ASSET_DIR}/veggie.jpg",
            "mime": "image/jpeg"
        },
        {
            "name": "BBQ Smoked Chicken",
            "desc": "Smoky glazed chicken breast, caramelized onions & mozzarella blend",
            "prices": {"Small": 299, "Large": 499},
            "category": PIZZA_CATEGORY_ID,
            "attr": [{"name": "Crust", "value": "Thin"}],
            "img": f"{ASSET_DIR}/bbq_chicken.jpg",
            "mime": "image/jpeg"
        },
        {
            "name": "Classic Sparkling Soda",
            "desc": "Chilled sparkling citrus soda served ice-cold",
            "prices": {"Can 330ml": 69, "Bottle 500ml": 119},
            "category": BEV_CATEGORY_ID,
            "attr": [{"name": "Serving", "value": "Chilled"}],
            "img": f"{ASSET_DIR}/beverage.jpg",
            "mime": "image/jpeg"
        }
    ],
    "Little Italy Trattoria": [
        {
            "name": "Neapolitan Margherita",
            "desc": "San Marzano tomatoes, fresh Fior di Latte mozzarella & sweet basil",
            "prices": {"Small": 229, "Large": 379},
            "category": PIZZA_CATEGORY_ID,
            "attr": [{"name": "Crust", "value": "Thin"}],
            "img": f"{ASSET_DIR}/margherita.png",
            "mime": "image/png"
        },
        {
            "name": "Quattro Formaggi",
            "desc": "Rich four-cheese blend of mozzarella, gorgonzola, parmesan & fontina",
            "prices": {"Small": 319, "Large": 519},
            "category": PIZZA_CATEGORY_ID,
            "attr": [{"name": "Crust", "value": "Thin"}],
            "img": f"{ASSET_DIR}/quattro_formaggi.jpg",
            "mime": "image/jpeg"
        },
        {
            "name": "Tuscan Garden Harvest",
            "desc": "Sun-dried tomatoes, roasted garlic, artichokes, and black kalamata olives",
            "prices": {"Small": 269, "Large": 429},
            "category": PIZZA_CATEGORY_ID,
            "attr": [{"name": "Crust", "value": "Thin"}],
            "img": f"{ASSET_DIR}/veggie.jpg",
            "mime": "image/jpeg"
        },
        {
            "name": "San Pellegrino Aranciata",
            "desc": "Authentic Italian sparkling orange beverage made with sun-ripened oranges",
            "prices": {"Can 330ml": 99, "Bottle 500ml": 149},
            "category": BEV_CATEGORY_ID,
            "attr": [{"name": "Serving", "value": "Chilled"}],
            "img": f"{ASSET_DIR}/beverage.jpg",
            "mime": "image/jpeg"
        }
    ],
    "Brooklyn Pizza Yard": [
        {
            "name": "Brooklyn NY Style Slice",
            "desc": "Authentic Brooklyn wide-fold crust, rich marinara & whole-milk mozzarella",
            "prices": {"Small": 249, "Large": 399},
            "category": PIZZA_CATEGORY_ID,
            "attr": [{"name": "Crust", "value": "Thin"}],
            "img": f"{ASSET_DIR}/margherita.png",
            "mime": "image/png"
        },
        {
            "name": "Spicy Jalapeno Pepperoni",
            "desc": "Crispy sliced cupping pepperoni with charred jalapeño slices and chili flakes",
            "prices": {"Small": 299, "Large": 489},
            "category": PIZZA_CATEGORY_ID,
            "attr": [{"name": "Crust", "value": "Thin"}],
            "img": f"{ASSET_DIR}/pepperoni.jpg",
            "mime": "image/jpeg"
        },
        {
            "name": "Smokehouse BBQ Chicken",
            "desc": "Tender chicken tossed in sweet hickory BBQ sauce with red onion & cilantro",
            "prices": {"Small": 319, "Large": 529},
            "category": PIZZA_CATEGORY_ID,
            "attr": [{"name": "Crust", "value": "Thin"}],
            "img": f"{ASSET_DIR}/bbq_chicken.jpg",
            "mime": "image/jpeg"
        },
        {
            "name": "Roasted Garlic & Mushroom",
            "desc": "Earthy portobello and white button mushrooms with caramelized roasted garlic",
            "prices": {"Small": 259, "Large": 419},
            "category": PIZZA_CATEGORY_ID,
            "attr": [{"name": "Crust", "value": "Thin"}],
            "img": f"{ASSET_DIR}/veggie.jpg",
            "mime": "image/jpeg"
        },
        {
            "name": "Brooklyn Craft Cola",
            "desc": "Micro-brewed cane sugar cola with aromatic vanilla and citrus notes",
            "prices": {"Can 330ml": 79, "Bottle 500ml": 129},
            "category": BEV_CATEGORY_ID,
            "attr": [{"name": "Serving", "value": "Chilled"}],
            "img": f"{ASSET_DIR}/beverage.jpg",
            "mime": "image/jpeg"
        }
    ],
    "Artisan Woodfire Pizzeria": [
        {
            "name": "Sourdough Margherita Di Bufala",
            "desc": "Naturally leavened sourdough with sweet plum tomatoes & creamy buffalo mozzarella",
            "prices": {"Small": 279, "Large": 459},
            "category": PIZZA_CATEGORY_ID,
            "attr": [{"name": "Crust", "value": "Thin"}],
            "img": f"{ASSET_DIR}/margherita.png",
            "mime": "image/png"
        },
        {
            "name": "Truffle Mushroom & Fontina",
            "desc": "Wild forest mushrooms, white truffle essence, melted fontina & fresh thyme",
            "prices": {"Small": 349, "Large": 579},
            "category": PIZZA_CATEGORY_ID,
            "attr": [{"name": "Crust", "value": "Thin"}],
            "img": f"{ASSET_DIR}/quattro_formaggi.jpg",
            "mime": "image/jpeg"
        },
        {
            "name": "Artisan Pepperoni & Hot Honey",
            "desc": "Artisanal dry-cured pepperoni drizzled with spicy habanero infused honey",
            "prices": {"Small": 329, "Large": 539},
            "category": PIZZA_CATEGORY_ID,
            "attr": [{"name": "Crust", "value": "Thin"}],
            "img": f"{ASSET_DIR}/pepperoni.jpg",
            "mime": "image/jpeg"
        },
        {
            "name": "Woodfired Mediterranean Veggie",
            "desc": "Flame-roasted zucchini, bell peppers, pitted kalamata olives and crumbled feta",
            "prices": {"Small": 299, "Large": 479},
            "category": PIZZA_CATEGORY_ID,
            "attr": [{"name": "Crust", "value": "Thin"}],
            "img": f"{ASSET_DIR}/veggie.jpg",
            "mime": "image/jpeg"
        },
        {
            "name": "Organic Lemon Iced Spritz",
            "desc": "Lightly sparkling cold-pressed organic lemon refresher with mint",
            "prices": {"Can 330ml": 89, "Bottle 500ml": 139},
            "category": BEV_CATEGORY_ID,
            "attr": [{"name": "Serving", "value": "Chilled"}],
            "img": f"{ASSET_DIR}/beverage.jpg",
            "mime": "image/jpeg"
        }
    ]
}

# 5. Seed Products for each tenant
for t_name, tid in tenant_ids.items():
    if t_name not in products_catalog:
        continue
    existing_prods = session.get(f"{BASE_URL}/api/catalog/products?tenantId={tid}&perPage=100").json()
    existing_prod_names = {p["name"] for p in existing_prods.get("data", [])}
    print(f"\n--- Seeding products for tenant {tid} ({t_name}) ---")
    
    for prod in products_catalog[t_name]:
        if prod["name"] in existing_prod_names:
            print(f"Product '{prod['name']}' already exists for tenant {tid}")
            continue
        with open(prod["img"], "rb") as f:
            files = {"image": (os.path.basename(prod["img"]), f, prod["mime"])}
            data = {
                "name": prod["name"],
                "description": prod["desc"],
                "priceConfiguration": json.dumps({"Size": {"priceType": "base", "availableOptions": prod["prices"]}}),
                "attributes": json.dumps(prod["attr"]),
                "tenantId": str(tid),
                "categoryId": prod["category"],
                "isPublish": "true"
            }
            res = session.post(f"{BASE_URL}/api/catalog/products", data=data, files=files, headers=headers)
            if res.status_code in (200, 201):
                pid = res.json().get("id")
                print(f"  Created product '{prod['name']}': ID {pid}")
            else:
                print(f"  Failed product '{prod['name']}': {res.status_code} {res.text}")

print("\nSeeding finished successfully!")
