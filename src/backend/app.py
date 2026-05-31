import os
import json
import logging
import psycopg2
import boto3

# Make Flask optional so it imports perfectly in Lambda without requiring Flask dependencies
try:
    from flask import Flask, request, jsonify
    has_flask = True
except ImportError:
    has_flask = False

# Set up logging for CloudWatch
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("geo_processor")

# Initialize Flask application only if available
if has_flask:
    app = Flask(__name__)
else:
    app = None


def get_db_connection():
    """Establishes connection to the PostgreSQL database and initializes PostGIS."""
    # Retrieve configuration from environment variables with safe defaults/logging
    db_host = os.environ.get("DB_HOST")
    db_user = os.environ.get("DB_USER", "dbadmin")
    db_password = os.environ.get("DB_PASSWORD")
    db_name = os.environ.get("DB_NAME", "postgres")

    if not db_host or not db_password:
        logger.error("Database connection credentials or host environment variables are missing!")
        raise ValueError("Missing database connection configurations in environment variables")

    try:
        # Connect to Postgres
        conn = psycopg2.connect(
            host=db_host,
            database=db_name,
            user=db_user,
            password=db_password,
            port=5432,
            connect_timeout=5
        )
        conn.autocommit = True
        
        # Initialize extensions and schema
        with conn.cursor() as cur:
            # Enable PostGIS extension
            logger.info("Verifying and enabling PostGIS extension...")
            cur.execute("CREATE EXTENSION IF NOT EXISTS postgis;")
            
            # Create feature storage table with Spatial column
            logger.info("Verifying and creating geojson_features table...")
            cur.execute("""
                CREATE TABLE IF NOT EXISTS geojson_features (
                    id SERIAL PRIMARY KEY,
                    properties JSONB,
                    geom GEOMETRY(Geometry, 4326),
                    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
                );
            """)
            
            # Create Spatial GIST index for fast query performance
            cur.execute("CREATE INDEX IF NOT EXISTS geojson_features_geom_idx ON geojson_features USING GIST (geom);")
            
        logger.info("Successfully connected to the database and verified database schema.")
        return conn
    except Exception as e:
        logger.error(f"Failed to connect or initialize the database: {e}")
        raise

def process_geojson_data(conn, geojson):
    """Parses, validates, and loads GeoJSON data into the PostgreSQL table."""
    if not isinstance(geojson, dict) or "type" not in geojson:
        logger.error("Invalid input format. Must be a valid JSON dictionary.")
        return 0

    features = []
    if geojson["type"] == "FeatureCollection":
        features = geojson.get("features", [])
    elif geojson["type"] == "Feature":
        features = [geojson]
    else:
        logger.error(f"Unsupported GeoJSON type: {geojson['type']}")
        return 0

    inserted_count = 0
    with conn.cursor() as cur:
        for feature in features:
            if not isinstance(feature, dict) or feature.get("type") != "Feature":
                logger.warning("Skipping feature: does not conform to the 'Feature' type.")
                continue

            properties = feature.get("properties", {})
            geometry = feature.get("geometry")

            if not geometry or not isinstance(geometry, dict):
                logger.warning("Skipping feature: missing or invalid 'geometry' attribute.")
                continue

            try:
                # ST_GeomFromGeoJSON processes geometry securely. Properties passed as parameterized JSONB.
                cur.execute(
                    """
                    INSERT INTO geojson_features (properties, geom)
                    VALUES (%s, ST_GeomFromGeoJSON(%s));
                    """,
                    (json.dumps(properties), json.dumps(geometry))
                )
                inserted_count += 1
            except Exception as e:
                logger.error(f"Failed to insert feature: {e}")
                continue

    logger.info(f"Successfully processed GeoJSON: loaded {inserted_count} feature(s) into database.")
    return inserted_count

def lambda_handler(event, context):
    """AWS Lambda entrypoint triggered by S3 bucket ObjectCreated events."""
    logger.info("Lambda trigger activated by S3 event.")
    s3_client = boto3.client("s3")
    total_loaded = 0

    try:
        conn = get_db_connection()
    except Exception as e:
        logger.error(f"Database initialization failed, exiting: {e}")
        return {"status": "error", "message": "Database connection failed"}

    try:
        # Loop through S3 upload records in the event
        for record in event.get("Records", []):
            bucket = record["s3"]["bucket"]["name"]
            key = record["s3"]["object"]["key"]
            logger.info(f"Retrieving GeoJSON file from S3: bucket={bucket}, key={key}")

            # Fetch file contents
            s3_response = s3_client.get_object(Bucket=bucket, Key=key)
            file_content = s3_response["Body"].read().decode("utf-8")
            geojson_data = json.loads(file_content)

            # Process and load data
            total_loaded += process_geojson_data(conn, geojson_data)

        conn.close()
        return {
            "status": "success",
            "inserted_features": total_loaded
        }
    except Exception as e:
        logger.error(f"Error during Lambda processing execution: {e}")
        if conn:
            conn.close()
        return {"status": "error", "message": str(e)}

# --- Flask Server REST API Endpoints (Container Mode) ---

if has_flask:
    @app.route("/health", methods=["GET"])
    def health():
        """Simple container health check endpoint."""
        return jsonify({"status": "healthy"}), 200

    @app.route("/process", methods=["POST"])
    def process():
        """Accepts a GeoJSON payload directly or a simulated S3 event payload."""
        payload = request.get_json(silent=True)
        if not payload:
            return jsonify({"status": "error", "message": "Invalid or missing JSON payload"}), 400

        try:
            conn = get_db_connection()
        except Exception as e:
            return jsonify({"status": "error", "message": f"Database unavailable: {e}"}), 500

        try:
            # Handle S3-notification format if forwarded by a webhook/SQS/event-bridge
            if "Records" in payload:
                s3_client = boto3.client("s3")
                loaded_count = 0
                for record in payload["Records"]:
                    bucket = record["s3"]["bucket"]["name"]
                    key = record["s3"]["object"]["key"]
                    logger.info(f"API processing S3 object: bucket={bucket}, key={key}")
                    
                    s3_response = s3_client.get_object(Bucket=bucket, Key=key)
                    file_content = s3_response["Body"].read().decode("utf-8")
                    geojson_data = json.loads(file_content)
                    loaded_count += process_geojson_data(conn, geojson_data)
            else:
                # Handle standard direct GeoJSON post payload
                loaded_count = process_geojson_data(conn, payload)

            conn.close()
            return jsonify({
                "status": "success",
                "inserted_features": loaded_count
            }), 200

        except Exception as e:
            logger.error(f"API processing error: {e}")
            if conn:
                conn.close()
            return jsonify({"status": "error", "message": str(e)}), 500

if __name__ == "__main__":
    # When container runs, execute the Flask application listening on all interfaces inside the container
    if has_flask:
        port = int(os.environ.get("PORT", 8080))
        logger.info(f"Starting API server on port {port}...")
        app.run(host="0.0.0.0", port=port)
    else:
        logger.error("Flask library not available. Cannot start web API server.")