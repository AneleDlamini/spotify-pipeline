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
def get_token(client_id, client_secret):
    url = "https://accounts.spotify.com/api/token"
    
    # POST request to the Spotify API token endpoint to obtain an access token.
    response = requests.post( 
        url,
        data = {'grant_type': 'client_credentials'}, # Specifies the type of access token requested.
        auth = (client_id, client_secret),
        timeout = 10  # Set a timeout for the request to avoid hanging indefinitely.
        )
    
    response.raise_for_status()  # Raise an error if the request was unsuccessful.
    return response.json()['access_token']  # Return the access token from the response.

# Lambda handler function that is triggered by an event.
# This function retrieves artist information from the Spotify API and saves it to an S3 bucket.
def handler(event, context):
    prefix = os.environ["PARAM_PREFIX"] # Retrieve the parameter prefix from environment variables.
    bucket = os.environ["RAW_BUCKET"] # Retrieve the S3 bucket name from environment variables.
    artist_ids = os.environ["ARTIST_IDS"].split(",") # Retrieve and split the artist IDs from environment variables.
    
    spotify_token = get_token(get_param(f"{prefix}/spotify/client_id"), get_param(f"{prefix}/spotify/client_secret")) 
    
    results = []
    
    # Loop through each artist ID and make a GET request to the Spotify API to retrieve artist information.
    for artist_id in artist_ids:
        r = requests.get(
            f"https://api.spotify.com/v1/artists/{artist_id}", 
            headers={"Authorization": f"Bearer {spotify_token}"}, # Include the access token in the request headers for authorization.
            timeout=10  # Set a timeout for the request to avoid hanging indefinitely.
        )
        
        r.raise_for_status()  # Raise an error if the request was unsuccessful.
        results.append(r.json())  # Append the JSON response to the results list.
        
        now = datetime.datetime.now(datetime.timezone.utc)
        key = f"artists/dt={now:%Y-%m-%d}/artist={now:%H%M%S}.json" # Create a unique S3 key for each artist's data based on the current date and artist ID.
        s3.put_object(Bucket=bucket, Key=key, Body=json.dumps(results).encode('utf-8')) # Upload the artist data to the specified S3 bucket.
        
        return {"saved_to": key, "artists": len(results)}