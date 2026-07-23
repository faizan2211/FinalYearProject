from django.http import JsonResponse
from django.views.decorators.csrf import csrf_exempt
import json
import requests
import urllib.parse
import re
import datetime
import random
from groq import Groq
from django.core.mail import send_mail
from pymongo import MongoClient
from django.conf import settings
from django.contrib.auth.hashers import make_password, check_password
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from rest_framework import status
import uuid
from bson.objectid import ObjectId

# Groq model configuration
GROQ_MODEL = "llama-3.1-8b-instant"
# Configure the Groq client once
groq_client = None
if hasattr(settings, 'GROQ_API_KEY') and settings.GROQ_API_KEY:
    groq_client = Groq(api_key=settings.GROQ_API_KEY)

# Connect to MongoDB Atlas
client = MongoClient(settings.MONGODB_URL)
db = client[settings.MONGODB_DB_NAME]
users_collection = db['users']

# Geoapify configuration
GEOAPIFY_API_KEY = "f4359d5a6ce148bd8127963c3d2bbe4c"

# Lahore bounding box (rect: lon_min,lat_min,lon_max,lat_max)
LAHORE_FILTER = "rect:74.1,31.35,74.55,31.65"
LAHORE_BIAS   = "proximity:74.3587,31.5204"

# POI categories for the Places API search
PLACE_CATEGORIES = (
    "catering.restaurant,catering.cafe,catering.fast_food,"
    "commercial.shopping_mall,commercial.supermarket,commercial.marketplace,"
    "entertainment,tourism,leisure,education,healthcare,amenity"
)

# 📍 VERIFIED COORDINATES (From Flutter App Constants)
# These override API results to ensure consistency across the app.
VERIFIED_LANDMARKS = {
    # Restaurants
    "arcadian": {"lat": 31.4671662, "lng": 74.2630385, "name": "Arcadian Cafe"},
    "haveli": {"lat": 31.586881432457453, "lng": 74.31137906266805, "name": "Haveli Restaurant"},
    "monal": {"lat": 31.509798118713224, "lng": 74.34106845280317, "name": "Monal Restaurant"},
    "spice bazaar": {"lat": 31.51874660533948, "lng": 74.35506622556233, "name": "Spice Bazaar"},
    "tuscany": {"lat": 31.516369087526467, "lng": 74.35180820972768, "name": "Tuscany Courtyard"},
    "villa": {"lat": 31.516656, "lng": 74.352725, "name": "Villa The Grand Buffet"},
    
    # Shopping Malls
    "amanah": {"lat": 31.466915, "lng": 74.316181, "name": "Amanah Mall"},
    "dolmen": {"lat": 31.468139, "lng": 74.435680, "name": "Dolmen Mall"},
    "emporium": {"lat": 31.467990, "lng": 74.265682, "name": "Emporium Mall"},
    "fortress": {"lat": 31.532322, "lng": 74.362893, "name": "Fortress Square Mall"},
    "mall of lahore": {"lat": 31.529314, "lng": 74.379026, "name": "Mall of Lahore"},
    "packages": {"lat": 31.471559, "lng": 74.355454, "name": "Packages Mall"},
    
    # Famous Places
    "delhi gate": {"lat": 31.582115, "lng": 74.326695, "name": "Delhi Gate"},
    "eiffel tower": {"lat": 31.355772, "lng": 74.1821538, "name": "Eiffel Tower (Bahria Town)"},
    "lahore fort": {"lat": 31.5882737, "lng": 74.3128776, "name": "Lahore Fort"},
    "shahi qila": {"lat": 31.5882737, "lng": 74.3128776, "name": "Shahi Qila (Lahore Fort)"},
    "museum": {"lat": 31.568734, "lng": 74.308140, "name": "Lahore Museum"},
    "minar": {"lat": 31.592596, "lng": 74.309209, "name": "Minar-e-Pakistan"},
    "shalimar": {"lat": 31.584243, "lng": 74.382818, "name": "Shalimar Gardens"},
    
    # Religious Places
    "andrew church": {"lat": 31.569716, "lng": 74.335622, "name": "St Andrew's Church"},
    "badshahi": {"lat": 31.5878521, "lng": 74.3099213, "name": "Badshahi Mosque"},
    "data darbar": {"lat": 31.579003, "lng": 74.3038113, "name": "Data Darbar Shrine"},
    "jamia mosque": {"lat": 31.3677792, "lng": 74.1853792, "name": "Grand Jamia Mosque"},
    "cathedral": {"lat": 31.565268, "lng": 74.317035, "name": "Sacred Heart Cathedral"},
    "wazir khan": {"lat": 31.583480, "lng": 74.323609, "name": "Wazir Khan Mosque"},
    
    # Hotels
    "avari": {"lat": 31.5590579, "lng": 74.3247871, "name": "Avari Hotel"},
    "four points": {"lat": 31.5615578, "lng": 74.3272535, "name": "Four Points by Sheraton"},
    "heritage": {"lat": 31.509561365500534, "lng": 74.34809398333987, "name": "Heritage Luxury Suites"},
    "indigo": {"lat": 31.507267945522173, "lng": 74.34858669683244, "name": "Indigo Heights Hotel"},
    "pc hotel": {"lat": 31.5528818, "lng": 74.3386959, "name": "Pearl Continental Hotel"},
    "ramada": {"lat": 31.53015819248054, "lng": 74.35460051032568, "name": "Ramada by Wyndham"},
}

GENERAL_RESPONSES = {"hello", "hi", "hey", "thanks", "thank you", "help"}


def _places_search(name_query: str):
    """Search via Geoapify Places API (v2) – great for restaurants, cafes, shops."""
    encoded = urllib.parse.quote(name_query)
    url = (
        f"https://api.geoapify.com/v2/places?"
        f"categories={PLACE_CATEGORIES}&"
        f"filter={LAHORE_FILTER}&"
        f"bias={LAHORE_BIAS}&"
        f"name={encoded}&"
        f"limit=1&"
        f"apiKey={GEOAPIFY_API_KEY}"
    )
    try:
        r = requests.get(url, timeout=5)
        if r.status_code == 200:
            features = r.json().get("features", [])
            if features:
                props = features[0]["properties"]
                return {
                    "lat": props.get("lat"),
                    "lng": props.get("lon"),
                    "name": props.get("name") or name_query.title(),
                }
    except Exception as e:
        print(f"[PlacesAPI Error] {e}")
    return None


def _geocode_search(query: str, lahore_only=True):
    """Search via Geoapify Autocomplete API – great for addresses, landmarks, areas."""
    # Always append Lahore context
    search_text = query if "lahore" in query.lower() else f"{query} Lahore"
    encoded = urllib.parse.quote(search_text)

    if lahore_only:
        url = (
            f"https://api.geoapify.com/v1/geocode/autocomplete?"
            f"text={encoded}&"
            f"filter={LAHORE_FILTER}&"
            f"bias={LAHORE_BIAS}&"
            f"limit=1&"
            f"apiKey={GEOAPIFY_API_KEY}"
        )
    else:
        url = (
            f"https://api.geoapify.com/v1/geocode/autocomplete?"
            f"text={encoded}&"
            f"filter=countrycode:pk&"
            f"bias={LAHORE_BIAS}&"
            f"limit=1&"
            f"apiKey={GEOAPIFY_API_KEY}"
        )
    try:
        r = requests.get(url, timeout=5)
        if r.status_code == 200:
            features = r.json().get("features", [])
            if features:
                props = features[0]["properties"]
                name = props.get("name") or props.get("formatted") or query.title()
                return {
                    "lat": props.get("lat"),
                    "lng": props.get("lon"),
                    "name": name,
                }
    except Exception as e:
        print(f"[GeocodeAPI Error] {e}")
    return None


def retrieve_places(user_query, limit=5):
    """Retrieve up to `limit` place documents most relevant to the `user_query`.
    Uses a case‑insensitive regex on `name` and `category` fields. Returns a formatted string
    that can be appended to the system prompt.
    """
    try:
        # Build regex for fuzzy matching
        regex = {"$regex": user_query, "$options": "i"}
        cursor = db['places'].find({"$or": [{"name": regex}, {"category": regex}]})
        docs = list(cursor.limit(limit))
        if not docs:
            return ""
        # Create readable summaries
        summaries = []
        for doc in docs:
            name = doc.get('name', 'Unknown')
            category = doc.get('category', 'Place')
            history = doc.get('history', '')
            # Trim history to first 120 chars for brevity
            snippet = (history[:120] + "...") if len(history) > 120 else history
            summaries.append(f"- {name} ({category}): {snippet}")
        return "Relevant places found in your database:\n" + "\n".join(summaries)
    except Exception as e:
        print(f"[RAG Retrieval error] {e}")
        return ""

# Define tool as a Python function for Gemini at global module level (required for SDK inspection)
def find_place_location(query: str, is_suggestion_request: bool = False):
    """Searches for a specific place or gets a list of suggestions for categories (like 'restaurants', 'malls', 'hotels'). Returns location details.

    Args:
        query: The name of the place, attraction, category, or 'places' for generic requests.
        is_suggestion_request: Set to True if user is requesting suggestions/recommendations rather than a single specific place.
    """
    # Normalize inputs
    q = (query or "").strip()
    q_lower = q.lower()

    found_places = []

    # 1) Check verified landmarks
    for key, data_val in VERIFIED_LANDMARKS.items():
        if key in q_lower:
            found_places.append(data_val)

    # 2) Heuristic category mapping
    search_query = q
    is_generic = any(word in q_lower for word in ["place", "spot", "suggestion", "recommendation", "attraction", "anything", "somewhere", "anywhere"]) or q_lower in ("places", "suggestions")
    if "restaurant" in q_lower or "food" in q_lower or "cafe" in q_lower:
        search_query = "Restaurant"
        is_generic = False
    elif "mall" in q_lower or "shopping" in q_lower or "market" in q_lower:
        search_query = "Shopping Mall"
        is_generic = False
    elif "hotel" in q_lower or "stay" in q_lower:
        search_query = "Hotel"
        is_generic = False

    # 3) Query MongoDB
    try:
        places_col = db['places']
        limit_count = 6 if is_suggestion_request or is_generic else 1
        if is_generic:
            db_places = list(places_col.find({}).sort("rating", -1).limit(limit_count))
        else:
            db_places = list(places_col.find({"$or": [
                {"name": {"$regex": search_query, "$options": "i"}},
                {"category": {"$regex": search_query, "$options": "i"}}
            ]}).sort("rating", -1).limit(limit_count))

        for db_place in db_places:
            found_places.append({
                "name": db_place.get("name"),
                "lat": db_place.get("lat"),
                "lng": db_place.get("lng"),
                "history": db_place.get("history", ""),
                "rating": db_place.get("rating", "")
            })
    except Exception:
        pass

    # 4) Geoapify fallback if still empty
    if not found_places:
        loc = _places_search(query)
        if loc:
            found_places.append(loc)
    if not found_places:
        loc = _geocode_search(query, lahore_only=True)
        if loc:
            found_places.append(loc)
    if not found_places:
        loc = _geocode_search(query, lahore_only=False)
        if loc:
            found_places.append(loc)

    return {"results": found_places} if found_places else {"error": "No matching places found."}

@csrf_exempt
def chat_response(request):
    if request.method != "POST":
        return JsonResponse({"error": "Only POST requests are allowed"}, status=405)

    try:
        data = json.loads(request.body)
    except json.JSONDecodeError:
        return JsonResponse({"reply": "I could not understand your message. Please try again!"})

    try:
        user_message = data.get("message", "").strip()
        if not user_message:
            return JsonResponse({"reply": "Please type a question or request for a place suggestion."})
        email = data.get("email", "").strip()

        # Retrieve contextual documents from the DB (RAG) - silently ignore DB errors
        try:
            rag_context = retrieve_places(user_message)
        except Exception:
            rag_context = ""

        # Build system prompt
        system_prompt = (
            "You are GeoAssistant, a warm, helpful local guide for Lahore, Pakistan. "
            "You help users find places, suggest restaurants, hotels, malls, and landmarks. "
            "ALWAYS use the 'find_place_location' tool when the user asks about any place, location, suggestion, direction, or nearby spot. "
            "If they ask for general recommendations or 'places to visit', call 'find_place_location' with query='places' and is_suggestion_request=True. "
            "When listing suggestions, describe each place briefly using the history provided. "
            "For greetings or general questions (like 'hi', 'hello', 'thanks', 'how are you'), respond warmly WITHOUT calling any tool. "
            "You can answer questions about Lahore's history, culture, food, and travel tips without using the tool. "
            "NEVER show raw coordinates (lat/lng numbers) to the user."
        )
        if rag_context:
            system_prompt += "\n" + rag_context

        # Setup Groq Tools
        groq_tools = [
            {
                "type": "function",
                "function": {
                    "name": "find_place_location",
                    "description": "Searches for a specific place or gets suggestions for categories like 'Restaurant', 'Hotel', 'Shopping Mall', 'Famous Place', 'Religious Place'. Returns location details.",
                    "parameters": {
                        "type": "object",
                        "properties": {
                            "query": {
                                "type": "string",
                                "description": "The name of the place, or a category like 'Restaurant', 'Hotel', 'Famous Place', 'Religious Place', 'Shopping Mall', or 'places' for generic requests."
                            },
                            "is_suggestion_request": {
                                "type": "boolean",
                                "description": "Set to True if user wants a list of suggestions rather than one specific place."
                            }
                        },
                        "required": ["query"]
                    }
                }
            }
        ]

        messages = [
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": user_message}
        ]

        if not groq_client:
            return JsonResponse({"reply": "I'm sorry, the AI service is not configured. Please contact support."})

        # ── Step 1: First Groq Call ────────────────────────────────────────
        try:
            response = groq_client.chat.completions.create(
                model=GROQ_MODEL,
                messages=messages,
                tools=groq_tools,
                tool_choice="auto",
                max_tokens=800
            )
        except Exception as groq_err:
            err_str = str(groq_err).lower()
            if "rate_limit" in err_str or "429" in err_str:
                return JsonResponse({"reply": "I'm receiving too many requests right now. Please wait a moment and try again!"})
            elif "401" in err_str or "authentication" in err_str:
                return JsonResponse({"reply": "I'm having trouble connecting to my AI service. Please try again later."})
            else:
                return JsonResponse({"reply": "I encountered a temporary issue. Please try again!"})

        reply = ""
        location = None
        response_data = {}
        response_message = response.choices[0].message

        # ── Step 2: Handle Tool Calls (if any) ────────────────────────────
        if response_message.tool_calls:
            tool_call = response_message.tool_calls[0]
            function_name = tool_call.function.name

            if function_name == "find_place_location":
                try:
                    args = json.loads(tool_call.function.arguments)
                except json.JSONDecodeError:
                    args = {}

                query = args.get("query", "")
                is_suggestion = args.get("is_suggestion_request", False)
                found_places = []

                # 1. Check VERIFIED_LANDMARKS dict
                q_clean = query.lower().strip()
                q_norm = re.sub(r'\b(restaurant|hotel|mall|park|shrine|mosque|gate|cafe|suites|place|places)\b', '', q_clean).strip()
                for key, data_val in VERIFIED_LANDMARKS.items():
                    if key in q_clean or (q_norm and key in q_norm):
                        found_places.append(dict(data_val))  # copy so we can enrich

                # 2. Normalize query for MongoDB category search
                search_query = query
                q_lower = query.lower().strip()
                is_generic = any(word in q_lower for word in ["place", "spot", "suggestion", "recommendation", "attraction", "anything", "somewhere", "anywhere"])

                if "restaurant" in q_lower or "food" in q_lower or "eat" in q_lower or "dine" in q_lower or "cafe" in q_lower:
                    search_query = "Restaurant"
                    is_generic = False
                elif "mall" in q_lower or "shopping" in q_lower or "market" in q_lower:
                    search_query = "Shopping Mall"
                    is_generic = False
                elif "hotel" in q_lower or "stay" in q_lower or "lodge" in q_lower or "room" in q_lower:
                    search_query = "Hotel"
                    is_generic = False
                elif "famous" in q_lower or "historic" in q_lower or "landmark" in q_lower or "monument" in q_lower or "park" in q_lower or "garden" in q_lower or "tourist" in q_lower or "visit" in q_lower:
                    search_query = "Famous Place"
                    is_generic = False
                elif "religious" in q_lower or "mosque" in q_lower or "church" in q_lower or "shrine" in q_lower or "temple" in q_lower or "masjid" in q_lower or "worship" in q_lower:
                    search_query = "Religious Place"
                    is_generic = False

                # 3. Search MongoDB - always run to enrich data with history/rating
                try:
                    places_col = db['places']
                    limit_count = 6 if is_suggestion else 3

                    if is_generic:
                        db_places = list(places_col.find({}).sort("rating", -1).limit(limit_count))
                    else:
                        db_places = list(places_col.find({"$or": [
                            {"name": {"$regex": search_query, "$options": "i"}},
                            {"category": {"$regex": search_query, "$options": "i"}}
                        ]}).sort("rating", -1).limit(limit_count))

                    if found_places and not is_suggestion:
                        # Enrich verified landmarks with history from DB
                        for db_place in db_places:
                            db_name = db_place.get("name", "").lower()
                            for fp in found_places:
                                fp_name = fp.get("name", "").lower()
                                if fp_name in db_name or db_name in fp_name:
                                    fp["history"] = db_place.get("history", "")
                                    fp["rating"] = db_place.get("rating", "")
                                    break
                    else:
                        for db_place in db_places:
                            found_places.append({
                                "name": db_place.get("name"),
                                "lat": db_place.get("lat"),
                                "lng": db_place.get("lng"),
                                "history": db_place.get("history", ""),
                                "rating": db_place.get("rating", "")
                            })
                except Exception as db_err:
                    print(f"[MongoDB Search Error] {db_err}")

                # 4. Geoapify fallback if still empty
                if not found_places:
                    try:
                        loc = _places_search(query)
                        if loc:
                            found_places.append(loc)
                    except Exception:
                        pass
                if not found_places:
                    try:
                        loc = _geocode_search(query, lahore_only=True)
                        if loc:
                            found_places.append(loc)
                    except Exception:
                        pass
                if not found_places:
                    try:
                        loc = _geocode_search(query, lahore_only=False)
                        if loc:
                            found_places.append(loc)
                    except Exception:
                        pass

                if found_places:
                    location = found_places[0]

                # 5. Send tool result back to Groq
                tool_result = {"results": found_places} if found_places else {"error": "No matching places found in Lahore."}

                messages.append(response_message)
                messages.append({
                    "role": "tool",
                    "tool_call_id": tool_call.id,
                    "name": function_name,
                    "content": json.dumps(tool_result)
                })

                # ── Step 3: Second Groq Call for final reply ──────────────
                try:
                    second_response = groq_client.chat.completions.create(
                        model=GROQ_MODEL,
                        messages=messages,
                        max_tokens=800
                    )
                    reply = second_response.choices[0].message.content
                except Exception as groq_err2:
                    err_str2 = str(groq_err2).lower()
                    if "rate_limit" in err_str2 or "429" in err_str2:
                        if found_places:
                            names = ", ".join([p.get("name", "") for p in found_places[:3] if p.get("name")])
                            reply = f"Here are some places I found: {names}. Tap to view on the map!"
                        else:
                            reply = "I'm a bit busy right now. Please wait a moment and try again!"
                    else:
                        reply = "I found the places but had trouble formatting the response. Please try again!"
        else:
            reply = response_message.content

        # ── Step 4: Final fallback if reply is still empty ───────────────
        if not reply or reply.strip() == "":
            reply = "Hello! I'm GeoAssistant, your Lahore city guide. Ask me about restaurants, malls, hotels, famous places, or any location!"

        response_data["reply"] = reply
        if location:
            response_data["location"] = location

        # Save to chat_history - silently ignore DB errors so they never crash the response
        if email:
            try:
                db['chat_history'].insert_one({
                    'email': email,
                    'user_message': user_message,
                    'bot_reply': reply,
                    'location': response_data.get('location'),
                    'timestamp': datetime.datetime.now(datetime.timezone.utc)
                })
            except Exception as db_err:
                print(f"[Mongo Log Error] {db_err}")

        return JsonResponse(response_data)

    except Exception as e:
        print(f"[chat_response Critical Error] {e}")
        return JsonResponse({"reply": "I'm experiencing a temporary issue. Please try again in a moment!"})

@api_view(['POST'])
@permission_classes([AllowAny])
def register_user(request):
    username = request.data.get('username') # This is the email
    email = request.data.get('email')
    password = request.data.get('password')

    if not username or not password:
        return Response({'error': 'Email and password are required'}, status=status.HTTP_400_BAD_REQUEST)

    # Check if user already exists
    if users_collection.find_one({'username': username}):
        return Response({'error': 'User already exists'}, status=status.HTTP_400_BAD_REQUEST)

    # Create user manually in MongoDB
    hashed_password = make_password(password)
    user_data = {
        'username': username,
        'email': email,
        'password': hashed_password,
        'token': str(uuid.uuid4())
    }
    users_collection.insert_one(user_data)
    
    return Response({
        'token': user_data['token'],
        'username': username,
        'message': 'User registered successfully to MongoDB Atlas'
    }, status=status.HTTP_201_CREATED)

@api_view(['POST'])
@permission_classes([AllowAny])
def login_user(request):
    username = request.data.get('username') # This is the email
    password = request.data.get('password')

    if not username or not password:
        return Response({'error': 'Email and password are required'}, status=status.HTTP_400_BAD_REQUEST)

    # Find user in MongoDB
    user = users_collection.find_one({'username': username})

    if user:
        if check_password(password, user['password']):
            return Response({
                'token': user['token'],
                'username': user['username'],
                'message': 'Login successful from MongoDB Atlas'
            }, status=status.HTTP_200_OK)
        else:
            return Response({'error': 'Invalid credentials'}, status=status.HTTP_401_UNAUTHORIZED)
    
    return Response({'error': 'You are not registered'}, status=status.HTTP_401_UNAUTHORIZED)


@api_view(['GET'])
@permission_classes([AllowAny])
def detect_city(request):
    lat = request.GET.get('lat')
    lng = request.GET.get('lng')
    if not lat or not lng:
        return Response({'error': 'Latitude (lat) and Longitude (lng) are required'}, status=status.HTTP_400_BAD_REQUEST)
    
    url = f"https://api.geoapify.com/v1/geocode/reverse?lat={lat}&lon={lng}&apiKey={GEOAPIFY_API_KEY}"
    try:
        r = requests.get(url, timeout=5)
        if r.status_code == 200:
            features = r.json().get("features", [])
            if features:
                props = features[0]["properties"]
                city = props.get("city") or props.get("county") or props.get("state") or "Lahore"
                # For elegant testing across the world, map results to Karachi if found, otherwise default to Lahore
                city_lower = city.lower()
                if "karachi" in city_lower:
                    city = "Karachi"
                else:
                    city = "Lahore"
                return Response({'city': city})
    except Exception as e:
        print(f"[ReverseGeocode Error] {e}")
    
    return Response({'city': 'Lahore'})


@api_view(['GET'])
@permission_classes([AllowAny])
def get_places(request):
    city = request.GET.get('city')
    category = request.GET.get('category')
    
    places_collection = db['places']
    
    # Auto-ensure coordinates and history descriptions are updated
    places_collection.update_one(
        {"name": {"$regex": "Haveli", "$options": "i"}},
        {"$set": {"history": "Haveli Restaurant is located in the 200-year-old Haveli Khalil Khan on Fort Road Food Street. Originally built during the British Raj, the historic mansion fell into disrepair after 1947 before being painstakingly restored by brothers Habib and Tariq Khan in 2005 to offer unparalleled dining and rooftop views.Aside from its traditional Mughlai and Lahori cuisine, the restaurant is famous for its panoramic, open-air rooftop seating. Patrons can enjoy unparalleled, up-close views of centuries-old landmarks including the Badshahi Mosque, the Lahore Fort, and Minar-e-Pakistan."}}
    )
    places_collection.update_one(
        {"name": {"$regex": "Arcadian", "$options": "i"}},
        {"$set": {"history": "Founded in 2012 by entrepreneur Imran Elahi, Arcadian Café is a beloved homegrown culinary brand in Lahore. Renowned for its Asian fusion, French-Italian, and Continental cuisine, it revolutionized the local dining scene with its upscale ambiance and signature 360-degree oblong beverage bar.The food Blends globally inspired flavors. Famous specialties include Bai Ze Chicken, Red Dragon Chicken, and Stuffed Chicken Butter with Spicy Sauce.The atmosphere serves as a popular gathering spot for families and friends, maintaining an upscale yet vibrant atmosphere with a staff of over 500 across the city.Its iconic oblong bar serves a wide variety of hand-crafted coffees, lattes, and specialty mocktails."}}
    )
    places_collection.update_one(
        {"name": {"$regex": "Tuscany", "$options": "i"}},
        {"$set": {
            "lat": 31.516369087526467, 
            "lng": 74.35180820972768,
            "history": "Tuscany Courtyard was founded by restaurateur Khurram Khan and partners. Following the massive success of their flagship Islamabad location, they brought the brand to Lahore in early 2017. Known for its castle-esque architecture and Italian-inspired cuisine, it has become a staple of Lahore's fine-dining scene.The imposing, castle-esque brick facade and castle pillars are designed to mimic a classic Italian countryside cottage. The interior features thick brick walls, arched windows, low wooden ceilings, and classic chandeliers.While originally focused strictly on Italian dishes like pizza and pasta, the menu has since expanded to include steaks, seafood, burgers, and a highly popular afternoon Hi-Tea."
        }}
    )
    places_collection.update_one(
        {"name": {"$regex": "Villa", "$options": "i"}},
        {"$set": {
            "lat": 31.516656, 
            "lng": 74.352725,
            "history": "Villa The Grand Buffet began as a Pan-Asian cloud kitchen in 2011. It evolved into a massive, live-cooking restaurant concept by December 2021 when its flagship location opened on MM Alam Road. The name \"Villa\" represents the Arabic concept of a house, bringing multiple global cuisines under one roof.The restaurant was created to fill a gap for premium, multi-cuisine, all-you-can-eat experiences in Lahore. It is well-known for its live food theatre, offering various global and local cuisines including a sushi bar, Korean hotpot, BBQ, and a large dessert section.In January 2023 expanded to Lake City in southern Lahore to serve surrounding communities.In 2024–2025 opened Villa World Buffet at DHA Phase 8 Broadway, their largest branch by seating capacity."
        }}
    )
    places_collection.update_one(
        {"name": {"$regex": "Monal", "$options": "i"}},
        {"$set": {"history": "Monal Restaurant Lahore was founded by entrepreneur Sheikh Luqman Afzal as an urban expansion of the famous Islamabad flagship The Monal. Located atop the Park and Ride Plaza in the heart of Gulberg's Liberty Chowk, it brings the brand's signature scenic views and diverse cuisine to the city.In 2006 the Monal Group was established when Sheikh Luqman opened the flagship fine-dining restaurant in the Margalla Hills National Park in Islamabad.Following the massive success and popularity of the Islamabad location, the brand expanded to major cities to offer a similar blend of Pakistani, Chinese, Thai, and Continental cuisines.The Lahore branch was opened to provide locals and tourists a premier rooftop dining experience, complete with panoramic views of the city, live music, and family-friendly terraces.Today, the Lahore branch continues to operate as a prominent culinary destination. It blends traditional country-style aesthetics with modern fine dining across its indoor halls and open-air terraces."}}
    )
    places_collection.update_one(
        {"name": {"$regex": "Spice Bazaar", "$options": "i"}},
        {"$set": {"history": "Spice Bazaar, established in 2014 by the Yum Group of Restaurants, revolutionized Lahore's dining scene by offering traditional Pakistani cuisine in an upscale, hygienic, and modern setting. It introduced a refined \"haveli-style\" courtyard ambiance to modern commercial areas, eventually expanding across Lahore, Multan, and Gujranwala.The restaurant's architecture is a blend of colonial, ethnic, and traditional haveli styles. It features calming indoor dining spaces and a beautiful open-air courtyard that is highly popular for daytime lunches, family gatherings, and high-tea buffets.Spice Bazaar is now recognized as a premier destination for traditional Pakistani food, serving everything from regional favorites to grand, celebratory platters.Key offerings include:Shahi Raan tendered mutton leg cooked to perfection and served on a bed of aromatic basmati rice.Mutton Kunna Slow-cooked mutton shanks made using legacy underground clay-pot methods."}}
    )

    query = {}
    if city:
        query['city'] = {"$regex": f"^{city}$", "$options": "i"}
    if category:
        # Match standard category keywords
        category_map = {
            "restaurant": "Restaurant",
            "restaurants": "Restaurant",
            "hotel": "Hotel",
            "hotels": "Hotel",
            "shopping mall": "Shopping Mall",
            "shopping malls": "Shopping Mall",
            "mall": "Shopping Mall",
            "malls": "Shopping Mall",
            "famous place": "Famous Place",
            "famous places": "Famous Place",
            "religious place": "Religious Place",
            "religious places": "Religious Place"
        }
        mapped = category_map.get(category.lower(), category)
        query['category'] = {"$regex": f"^{mapped}$", "$options": "i"}
        
    places = list(places_collection.find(query).sort("rating", -1))
    for p in places:
        p['_id'] = str(p['_id'])
    
    return Response(places)


@api_view(['GET', 'DELETE'])
@permission_classes([AllowAny])
def chat_history(request):
    if request.method == 'DELETE':
        try:
            data = request.data
            email = data.get('email', '').strip()
            ids = data.get('ids', [])
            
            if not email:
                return Response({'error': 'Email is required'}, status=status.HTTP_400_BAD_REQUEST)
                
            if not ids:
                return Response({'error': 'No IDs provided for deletion'}, status=status.HTTP_400_BAD_REQUEST)
                
            object_ids = []
            for id_str in ids:
                try:
                    object_ids.append(ObjectId(id_str))
                except Exception:
                    pass
                    
            if object_ids:
                db['chat_history'].delete_many({
                    'email': email,
                    '_id': {'$in': object_ids}
                })
            
            return Response({'message': 'Deleted successfully'}, status=status.HTTP_200_OK)
        except Exception as e:
            return Response({'error': str(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)

    # GET request handling
    email = request.GET.get('email', '').strip()
    if not email:
        return Response({'error': 'Email parameter is required'}, status=status.HTTP_400_BAD_REQUEST)

    try:
        # Retrieve history logs matching email sorted by newest first
        logs = list(db['chat_history'].find({'email': email}).sort('timestamp', -1))
        
        history_list = []
        for log in logs:
            history_list.append({
                'id': str(log['_id']),
                '_id': str(log['_id']),
                'user_message': log.get('user_message', ''),
                'bot_reply': log.get('bot_reply', ''),
                'location': log.get('location'),
                'timestamp': log.get('timestamp').isoformat() if log.get('timestamp') else None
            })
            
        return Response({'history': history_list}, status=status.HTTP_200_OK)
    except Exception as e:
        return Response({'error': str(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


@api_view(['POST'])
@permission_classes([AllowAny])
def forgot_password_view(request):
    username = request.data.get('email', '').strip()  # Users identify by email as username
    if not username:
        return Response({'error': 'Email address is required'}, status=status.HTTP_400_BAD_REQUEST)

    try:
        user = users_collection.find_one({'username': username})
        if not user:
            return Response({'error': 'No registered user found with this email'}, status=status.HTTP_404_NOT_FOUND)

        # Generate 6-digit OTP
        otp = str(random.randint(100000, 999999))
        expiry = datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(minutes=10)

        # Update user with OTP info
        users_collection.update_one(
            {'_id': user['_id']},
            {'$set': {
                'otp': otp,
                'otp_expiry': expiry
            }}
        )

        # Send email via Django Mail
        subject = "GeoAssistant - Password Reset Verification Code"
        body = (
            f"Hello,\n\n"
            f"You requested a password reset for your GeoAssistant account.\n"
            f"Your 2-Step Verification Code is: {otp}\n\n"
            f"This code will expire in 10 minutes.\n\n"
            f"If you did not request this, please ignore this email."
        )
        send_mail(
            subject=subject,
            message=body,
            from_email=settings.EMAIL_HOST_USER,
            recipient_list=[username],
            fail_silently=False
        )

        return Response({'message': 'Verification code sent to your email'}, status=status.HTTP_200_OK)
    except Exception as e:
        return Response({'error': str(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


@api_view(['POST'])
@permission_classes([AllowAny])
def reset_password_view(request):
    username = request.data.get('email', '').strip()
    otp = request.data.get('otp', '').strip()
    new_password = request.data.get('new_password', '')

    if not username or not otp or not new_password:
        return Response({'error': 'Email, verification code, and new password are required'}, status=status.HTTP_400_BAD_REQUEST)

    try:
        user = users_collection.find_one({'username': username})
        if not user:
            return Response({'error': 'No user found with this email'}, status=status.HTTP_404_NOT_FOUND)

        # Validate OTP
        db_otp = user.get('otp')
        db_expiry = user.get('otp_expiry')

        if not db_otp or db_otp != otp:
            return Response({'error': 'Invalid verification code'}, status=status.HTTP_400_BAD_REQUEST)

        # Handle timezone-aware datetime comparison
        now = datetime.datetime.now(datetime.timezone.utc)
        
        # Ensure db_expiry is timezone-aware
        if db_expiry:
            if db_expiry.tzinfo is None:
                db_expiry = db_expiry.replace(tzinfo=datetime.timezone.utc)
                
            if now > db_expiry:
                return Response({'error': 'Verification code has expired'}, status=status.HTTP_400_BAD_REQUEST)
        else:
            return Response({'error': 'Invalid verification session'}, status=status.HTTP_400_BAD_REQUEST)

        # Update password
        hashed_password = make_password(new_password)
        users_collection.update_one(
            {'_id': user['_id']},
            {
                '$set': {'password': hashed_password},
                '$unset': {'otp': "", 'otp_expiry': ""}
            }
        )

        return Response({'message': 'Password has been reset successfully'}, status=status.HTTP_200_OK)
    except Exception as e:
        return Response({'error': str(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)
