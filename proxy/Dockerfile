# Dockerfile for the custom FastAPI proxy
FROM python:3.11-slim

WORKDIR /app

# Copy requirements first to leverage Docker layer caching
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy your proxy server code
COPY proxy_server.py .

# Expose the port the proxy will run on (default is 8000 in your script via argparse)
# This is informational; the actual port is determined by the --port argument to your script.
EXPOSE 8000

# ENTRYPOINT makes "python proxy_server.py" the command.
ENTRYPOINT ["python", "proxy_server.py"]

# CMD provides default arguments to proxy_server.py if none are given in Kubernetes.
# These are arguments to proxy_server.py, which will then pass --host and --port to uvicorn.run().
# You can override these entirely with `args` in your Kubernetes deployment.
CMD ["--host", "0.0.0.0", "--port", "8000"]
