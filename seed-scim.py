#!/usr/bin/env python3
"""Seed the SCIM server with test users and groups.

Usage:
    # Load the 10 curated users from scim-seed-data.json
    python3 seed-scim.py

    # Generate 1000 random users instead
    python3 seed-scim.py --generate 1000

    # Custom server URL and token
    python3 seed-scim.py --url http://localhost:8585 --token my-token

    # Clear all existing resources first
    python3 seed-scim.py --clear
"""

import argparse
import json
import random
import string
import sys
import urllib.request
import urllib.error
from datetime import date, timedelta
from pathlib import Path

SEED_FILE = Path(__file__).parent / "scim-seed-data.json"

# --- Name pools for random generation ---

FIRST_NAMES = [
    "Alexander", "Andrea", "Anna", "Barbara", "Bernd", "Birgit", "Caroline",
    "Christian", "Christina", "Claudia", "Daniel", "David", "Elena", "Eva",
    "Felix", "Florian", "Frank", "Friedrich", "Georg", "Hannah", "Hans",
    "Heinz", "Helena", "Jan", "Jana", "Johannes", "Julia", "Juliane",
    "Jurgen", "Karl", "Karsten", "Katharina", "Klaus", "Laura", "Lena",
    "Lisa", "Lukas", "Manfred", "Marcel", "Maria", "Markus", "Martin",
    "Matthias", "Max", "Melanie", "Michael", "Monika", "Nadine", "Nicole",
    "Oliver", "Patrick", "Paul", "Peter", "Petra", "Ralf", "Robert",
    "Roland", "Sabine", "Sandra", "Sebastian", "Simon", "Stefan", "Stefanie",
    "Susanne", "Thomas", "Tobias", "Ulrich", "Ursula", "Uwe", "Wolfgang",
]

MIDDLE_NAMES = [
    None, None, None, None, None,  # ~50% chance of no middle name
    "Alexander", "Elisabeth", "Friedrich", "Hans", "Johann",
    "Kathrin", "Ludwig", "Marie", "Sophie", "Wilhelm",
]

LAST_NAMES = [
    "Albrecht", "Arnold", "Bauer", "Baumann", "Beck", "Becker", "Berger",
    "Brandt", "Braun", "Busch", "Dietrich", "Ernst", "Fischer", "Frank",
    "Fuchs", "Gross", "Haas", "Hartmann", "Heinrich", "Hermann", "Hoffmann",
    "Huber", "Kaiser", "Keller", "Klein", "Koch", "Krause", "Kruger",
    "Lang", "Lehmann", "Lorenz", "Ludwig", "Maier", "Meier", "Meyer",
    "Muller", "Neumann", "Peters", "Richter", "Roth", "Schaefer", "Schmidt",
    "Schneider", "Scholz", "Schreiber", "Schulz", "Schwarz", "Seidel",
    "Wagner", "Weber", "Werner", "Winkler", "Winter", "Wolf", "Zimmermann",
]

DEPARTMENTS = [
    "Engineering", "Finance", "Human Resources", "IT Operations", "Legal",
    "Marketing", "Sales", "Product Management", "Quality Assurance", "Support",
]

TITLES = {
    "Engineering": ["Software Developer", "Senior Developer", "DevOps Engineer", "Software Architect", "Tech Lead"],
    "Finance": ["Financial Analyst", "Controller", "Accountant", "Finance Manager", "Treasury Analyst"],
    "Human Resources": ["HR Manager", "Recruiter", "HR Business Partner", "Compensation Analyst", "Training Specialist"],
    "IT Operations": ["System Administrator", "Network Engineer", "IT Support Specialist", "Cloud Engineer", "Security Analyst"],
    "Legal": ["Legal Counsel", "Compliance Officer", "Contract Manager", "Paralegal", "Data Protection Officer"],
    "Marketing": ["Marketing Specialist", "Content Manager", "SEO Analyst", "Brand Manager", "Campaign Manager"],
    "Sales": ["Account Executive", "Sales Manager", "Business Development Rep", "Key Account Manager", "Sales Engineer"],
    "Product Management": ["Product Manager", "Product Owner", "Business Analyst", "UX Researcher", "Scrum Master"],
    "Quality Assurance": ["QA Engineer", "Test Lead", "Automation Engineer", "QA Analyst", "Performance Tester"],
    "Support": ["Support Engineer", "Customer Success Manager", "Technical Writer", "Support Team Lead", "Helpdesk Analyst"],
}

GROUPS_FOR_GENERATED = [
    "Engineering", "Finance", "Human Resources", "IT Operations", "Legal",
    "Marketing", "Sales", "Product Management", "Quality Assurance", "Support",
    "All Employees",
]


def scim_request(base_url, method, path, token, data=None):
    """Make a SCIM API request. Uses only stdlib."""
    url = f"{base_url.rstrip('/')}/{path.lstrip('/')}"
    body = json.dumps(data).encode() if data else None
    req = urllib.request.Request(url, data=body, method=method)
    req.add_header("Authorization", f"Bearer {token}")
    if data:
        req.add_header("Content-Type", "application/scim+json")
    try:
        with urllib.request.urlopen(req) as resp:
            if resp.status == 204:
                return None
            return json.loads(resp.read().decode())
    except urllib.error.HTTPError as e:
        error_body = e.read().decode() if e.fp else ""
        print(f"  ERROR {e.code}: {error_body[:200]}", file=sys.stderr)
        return None


def build_scim_user(user):
    """Convert a seed data user dict to a SCIM User payload."""
    schemas = ["urn:ietf:params:scim:schemas:core:2.0:User"]
    name = {
        "givenName": user["givenName"],
        "familyName": user["familyName"],
    }
    if user.get("middleName"):
        name["middleName"] = user["middleName"]
    name["formatted"] = " ".join(
        filter(None, [user["givenName"], user.get("middleName"), user["familyName"]])
    )

    payload = {
        "schemas": schemas,
        "userName": user["userName"],
        "name": name,
        "displayName": f"{user['givenName']} {user['familyName']}",
        "emails": [{"value": user["email"], "type": "work", "primary": True}],
        "active": True,
        "title": user.get("title", ""),
    }

    # Enterprise extension
    enterprise = {}
    if user.get("employeeNumber"):
        enterprise["employeeNumber"] = user["employeeNumber"]
    if user.get("department"):
        enterprise["department"] = user["department"]
    if enterprise:
        schemas.append("urn:ietf:params:scim:schemas:extension:enterprise:2.0:User")
        payload["urn:ietf:params:scim:schemas:extension:enterprise:2.0:User"] = enterprise

    return payload


def generate_random_users(count):
    """Generate N random users."""
    used_usernames = set()
    users = []
    for i in range(count):
        first = random.choice(FIRST_NAMES)
        middle = random.choice(MIDDLE_NAMES)
        last = random.choice(LAST_NAMES)
        department = random.choice(DEPARTMENTS)
        title = random.choice(TITLES[department])

        # Ensure unique username
        base_username = f"{first.lower()}.{last.lower()}"
        username = base_username
        suffix = 1
        while username in used_usernames:
            suffix += 1
            username = f"{base_username}{suffix}"
        used_usernames.add(username)

        # Entry date: random within last 5 years
        entry = date.today() - timedelta(days=random.randint(30, 1825))

        # ~20% get an exit date in the future
        exit_date = None
        if random.random() < 0.2:
            exit_date = (date.today() + timedelta(days=random.randint(30, 365))).isoformat()

        user = {
            "userName": username,
            "givenName": first,
            "familyName": last,
            "email": f"{username}@example.com",
            "department": department,
            "title": title,
            "employeeNumber": f"EMP-{i + 1:04d}",
            "entryDate": entry.isoformat(),
            "exitDate": exit_date,
        }
        if middle:
            user["middleName"] = middle
        users.append(user)
    return users


def generate_groups_for_users(users):
    """Create department-based groups from the generated users."""
    dept_members = {}
    all_members = []
    for u in users:
        dept = u.get("department", "Other")
        dept_members.setdefault(dept, []).append(u["userName"])
        all_members.append(u["userName"])

    groups = [{"displayName": dept, "members": members} for dept, members in dept_members.items()]
    groups.append({"displayName": "All Employees", "members": all_members})
    return groups


def clear_resources(base_url, token):
    """Delete all existing users and groups."""
    print("Clearing existing resources...")
    for resource in ("Users", "Groups"):
        result = scim_request(base_url, "GET", resource, token)
        if not result or "Resources" not in result:
            continue
        for r in result["Resources"]:
            scim_request(base_url, "DELETE", f"{resource}/{r['id']}", token)
        print(f"  Deleted {len(result['Resources'])} {resource.lower()}")


def seed(base_url, token, users, groups):
    """Create users and groups in the SCIM server."""
    # Track userName -> SCIM id for group membership
    user_id_map = {}

    print(f"\nCreating {len(users)} users...")
    for i, user in enumerate(users, 1):
        payload = build_scim_user(user)
        result = scim_request(base_url, "POST", "Users", token, payload)
        if result and "id" in result:
            user_id_map[user["userName"]] = result["id"]
            status = "ok"
        else:
            status = "FAILED"
        # Print progress every user for small sets, every 50 for large
        if len(users) <= 50 or i % 50 == 0 or i == len(users):
            print(f"  [{i}/{len(users)}] {user['userName']} - {status}")

    print(f"\nCreating {len(groups)} groups...")
    for group in groups:
        members = []
        for username in group["members"]:
            if username in user_id_map:
                members.append({"value": user_id_map[username], "display": username})
        payload = {
            "schemas": ["urn:ietf:params:scim:schemas:core:2.0:Group"],
            "displayName": group["displayName"],
            "members": members,
        }
        result = scim_request(base_url, "POST", "Groups", token, payload)
        status = "ok" if result and "id" in result else "FAILED"
        member_count = len(members)
        print(f"  {group['displayName']} ({member_count} members) - {status}")

    print(f"\nDone. {len(user_id_map)} users and {len(groups)} groups created.")


def main():
    parser = argparse.ArgumentParser(description="Seed the SCIM server with test data")
    parser.add_argument("--url", default="http://localhost:8585", help="SCIM server base URL")
    parser.add_argument("--token", default="scim-dev-token", help="Bearer token")
    parser.add_argument("--generate", type=int, metavar="N", help="Generate N random users instead of using seed file")
    parser.add_argument("--seed-file", type=str, default=str(SEED_FILE), help="Path to seed data JSON file")
    parser.add_argument("--clear", action="store_true", help="Clear all existing resources before seeding")
    args = parser.parse_args()

    if args.clear:
        clear_resources(args.url, args.token)

    if args.generate:
        print(f"Generating {args.generate} random users...")
        users = generate_random_users(args.generate)
        groups = generate_groups_for_users(users)
    else:
        seed_path = Path(args.seed_file)
        if not seed_path.exists():
            print(f"Seed file not found: {seed_path}", file=sys.stderr)
            sys.exit(1)
        data = json.loads(seed_path.read_text())
        users = data["users"]
        groups = data.get("groups", [])
        print(f"Loaded {len(users)} users and {len(groups)} groups from {seed_path.name}")

    seed(args.url, args.token, users, groups)


if __name__ == "__main__":
    main()
