import pymongo
import requests
import time

API_KEY = "68D4659D3FFB489F8039CF4EB39D5370"
client = pymongo.MongoClient('mongodb+srv://fyp1912_db_user:geoassist@cluster0.bflfzf8.mongodb.net/?appName=Cluster0')
db = client['geo_assistant_db']
places_col = db['places']

places = list(places_col.find({}))
print(f"Starting TripAdvisor update for {len(places)} places...")

headers = {"accept": "application/json"}

updated_count = 0

for p in places:
    name = p.get('name')
    city = p.get('city', 'Lahore')
    search_query = f"{name} {city}"
    
    # Check if reviews already exist, skip if so to save API calls
    current_history = p.get('history', '')
    if "--- Real User Reviews ---" in current_history:
        print(f"Skipping {name}: Reviews already fetched.")
        continue
        
    print(f"\nProcessing: {name}...")
    
    # 1. Search for Location ID
    search_url = f"https://api.content.tripadvisor.com/api/v1/location/search?key={API_KEY}&searchQuery={search_query}&language=en"
    try:
        res = requests.get(search_url, headers=headers)
    except Exception as e:
        print(f"  [!] Request error: {e}")
        continue
        
    if res.status_code != 200:
        print(f"  [!] Search failed for {name}: {res.status_code}")
        continue
        
    data = res.json()
    if not data.get('data'):
        print(f"  [-] No TripAdvisor match found for {name}.")
        continue
        
    location_id = data['data'][0]['location_id']
    print(f"  [+] Found location ID: {location_id}")
    
    # 2. Get Details (Rating)
    details_url = f"https://api.content.tripadvisor.com/api/v1/location/{location_id}/details?key={API_KEY}&language=en&currency=USD"
    details_res = requests.get(details_url, headers=headers)
    rating = None
    if details_res.status_code == 200:
        details_data = details_res.json()
        raw_rating = details_data.get('rating')
        if raw_rating:
            try:
                rating = float(raw_rating)
            except ValueError:
                pass

    # 3. Get Reviews
    reviews_url = f"https://api.content.tripadvisor.com/api/v1/location/{location_id}/reviews?key={API_KEY}&language=en"
    reviews_res = requests.get(reviews_url, headers=headers)
    reviews_text = ""
    if reviews_res.status_code == 200:
        reviews_data = reviews_res.json().get('data', [])
        if reviews_data:
            reviews_text = "\n\n--- Real User Reviews ---\n"
            for r in reviews_data[:3]: # Take top 3 reviews
                text = r.get('text', '').replace('\n', ' ').strip()
                r_rating = r.get('rating', '?')
                if text:
                    reviews_text += f'"{text}" ({r_rating}/5)\n\n'
    
    # 4. Update Database
    update_fields = {}
    if rating is not None:
        update_fields['rating'] = rating
        print(f"  [+] New Rating: {rating}")
        
    if reviews_text:
        update_fields['history'] = current_history + reviews_text
        print(f"  [+] Appended reviews to history.")
            
    if update_fields:
        places_col.update_one({'_id': p['_id']}, {'$set': update_fields})
        print(f"  [OK] Successfully updated database for {name}.")
        updated_count += 1
    else:
        print(f"  [-] No new rating or reviews found for {name}.")
        
    # Rate limit protection
    time.sleep(0.5)

print(f"\nFinished updating! Added TripAdvisor data to {updated_count} places.")
