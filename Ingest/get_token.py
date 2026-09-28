# This script is used to obtain a refresh token from Spotify's API using the Spotipy library.

import spotipy
import subprocess # Used to run shell commands from within Python.
from spotipy.oauth2 import SpotifyOAuth

# Retrieve Spotify API credentials from AWS Systems Manager Parameter Store and uses them to authenticate with Spotify's API.
def param(name):
    out = subprocess.run( 
        ["aws", "ssm", "get-parameter", "--name", f"/spotify-pipeline/spotify/{name}", 
         "--with-decryption", "--query", "Parameter.Value", "--output", "text"],
        capture_output=True, text=True, check=True
    )
    return out.stdout.strip()

# Set up the SpotifyOAuth object with your credentials and desired scopes
auth = SpotifyOAuth(
    client_id=param("client_id"),
    client_secret=param("client_secret"),
    redirect_uri="http://127.0.0.1:9090/callback",
    scope="user-top-read user-read-recently-played user-read-currently-playing",
    open_browser=True,
)

token_info = auth.get_access_token(as_dict=True)  # Get the access token from Spotify
print("REFRESH TOKEN:", token_info["refresh_token"])