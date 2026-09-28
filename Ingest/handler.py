import os
import json
import datetime
import boto3 # AWS library for Python, used to interact with AWS services.
import requests # Library for making HTTP requests in Python.

# Create AWS clients to interact with SSM and S3 services.
ssm = boto3.client('ssm')
s3 = boto3.client('s3') 

# Retrieve a parameter from AWS Systems Manager Parameter Store.
def get_param(name):
    return ssm.get_parameter(Name=name, WithDecryption=True)['Parameter']['Value'] 


# Retrieve Spotify API credentials from AWS SSM Parameter Store.
def get_token(client_id, client_secret, refresh_token):
    url = "https://accounts.spotify.com/api/token"
    
    # POST request to the Spotify API token endpoint to obtain an access token.
    response = requests.post( 
        url,
        data = {'grant_type': "refresh_token", 'refresh_token': refresh_token}, # Specify the grant type and include the refresh token in the request body.
        auth = (client_id, client_secret),
        timeout = 10  # Set a timeout for the request to avoid hanging indefinitely.
        )
    # Check if the response status code is not 200 (OK). If not, print an error message with the status code and response text.
    if response.status_code != 200:
        print("SPOTIFY ERROR:", response.status_code, response.text)
    response.raise_for_status()
   # response.raise_for_status()  # Raise an error if the request was unsuccessful.
    return response.json()['access_token']  # Return the access token from the response.

# Lambda handler function that is triggered by an event.
# This function retrieves artist information from the Spotify API and saves it to an S3 bucket.
def handler(event, context):
    prefix = os.environ["PARAM_PREFIX"] # Retrieve the parameter prefix from environment variables.
    bucket = os.environ["RAW_BUCKET"] # Retrieve the S3 bucket name from environment variables.
   # artist_ids = os.environ["ARTIST_IDS"].split(",") # Retrieve and split the artist IDs from environment variables.
    
    spotify_token = get_token(
        get_param(f"{prefix}/spotify/client_id"), 
        get_param(f"{prefix}/spotify/client_secret"), 
        get_param(f"{prefix}/spotify/refresh_token")) 
    
    # Make a GET request to the Spotify API to retrieve the user's recently played tracks.
    r = requests.get(
        "https://api.spotify.com/v1/me/player/recently-played", 
        headers={"Authorization": f"Bearer {spotify_token}"},
        params={"limit" : 50},
        timeout=10,
    )
        
    if r.status_code != 200:
        print("SPOTIFY ERROR:", r.status_code, r.text)
    r.raise_for_status()  # Raise an error if the request was unsuccessful.
    data = (r.json())  # Parse the JSON response from the Spotify API.
        
    now = datetime.datetime.now(datetime.timezone.utc)
    key = f"recently_played/dt={now:%Y-%m-%d}/played_{now:%H%M%S}.json" # Create a unique S3 key based on the current date and time for storing the recently played tracks data.
    s3.put_object(Bucket=bucket, Key=key, Body=json.dumps(data).encode('utf-8')) # Upload the artist data to the specified S3 bucket.
    
    return {"saved_to": key, "tracks": len(data.get("items", []))}