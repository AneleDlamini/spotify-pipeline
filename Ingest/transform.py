
import json
import io
import pandas as pd
import boto3
import urllib.parse

# Create an S3 client to interact with the S3 service.
s3 = boto3.client('s3')

# Define the fields to be extracted from the data.
FIELDS = ["played_at", "track_name", "track_id", "artist_names", "album_name", "album_release_date", "duration_sec"]

# Function to flatten the nested JSON structure into a list of dictionaries.
def flatten(payload):
    rows = []
    
    # Iterate through each item in the payload's "items" list, extracting relevant information and appending it to the rows list.
    for item in payload.get("items", []):
        track = item.get("track") or {}
        album = track.get("album") or {}
        artists = track.get("artists") or []
        rows.append({
            "played_at": item.get("played_at"),
            "track_name": track.get("name"),
            "track_id": track.get("id"),
            "artist_names": ", ".join([artist.get("name") for artist in artists]), # Join artist names with a comma and space
            "album_name": album.get("name"),
            "album_release_date": album.get("release_date"),
            "duration_sec": round((track.get("duration_ms") or 0) / 1000, 1), # Convert milliseconds to seconds and round to 1 decimal place
        })
        
    return rows


# Lambda handler function that processes incoming S3 events, transforms the data, and uploads the transformed data back to S3.
def handler(event, context):
    results = []
    
    for record in event["Records"]:
        bucket = record["s3"]["bucket"]["name"]
        key = urllib.parse.unquote_plus(record["s3"]["object"]["key"])                             # Decode the S3 object key
        
        payload = json.loads(s3.get_object(Bucket=bucket, Key=key)["Body"].read())                 # Read the S3 object and parse it as JSON
        df = pd.DataFrame(flatten(payload))                                                        # Create a DataFrame from the flattened data
        df["played_at"] = pd.to_datetime(df["played_at"], format = "ISO8601", utc=True)            # Convert the "played_at" field to datetime format
        
        buffer = io.BytesIO()  # Create an in-memory bytes buffer
        df.to_parquet(buffer, engine="pyarrow", compression="snappy", index=False)                 # Write the DataFrame to the buffer in Parquet format
        
        dest = key.replace("recently_played/", "processed/recently_played/", 1).replace(".json", ".parquet")  # Define the destination key for the transformed data
        s3.put_object(Bucket=bucket, Key=dest, Body=buffer.getvalue())                             # Upload the transformed data to S3
        
        results.append({"source": key, "dest": dest, "rows": len(df)})                             # Append the source and destination information to the results list
        
    return {"files" : results}                                                                     # Return the results as a dictionary