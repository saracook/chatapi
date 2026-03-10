#!/bin/bash
# Start multi-GPU chatbot with load balancer and queueing
# Handles unlimited concurrent requests across 2 GPU workers

cd "$(dirname "$0")"

echo "=== Multi-GPU Chatbot with Smart Queueing ==="
echo ""

# Check if instance is running, start it if not
if ! apptainer instance list | grep -q chatapi; then
    echo "Starting chatapi instance..."
    apptainer instance start --nv --bind "$PWD:$PWD" chatbot.sif chatapi
    sleep 2
    echo "✓ Instance started"
else
    echo "✓ Instance already running"
fi

# Kill any existing single worker on port 7000
echo "Stopping any existing workers..."
pkill -f "uvicorn app.main:app.*7000" || true
pkill -f "uvicorn app.main:app.*800[12]" || true
pkill -f "load_balancer.py" || true
sleep 2

# Start Worker 1 on GPU 0 (port 7001)
echo "Starting Worker 1 (GPU 0) on port 7001..."
APPTAINERENV_WORKER_GPU=cuda:0 apptainer exec --nv instance://chatapi /opt/chatbot-env/bin/uvicorn app.main:app \
  --host 127.0.0.1 \
  --port 7001 \
  --log-level warning &

WORKER1_PID=$!
echo $WORKER1_PID > .worker1.pid
echo "  → Worker 1 PID: $WORKER1_PID"

# Give first worker time to start
sleep 3

# Start Worker 2 on GPU 1 (port 7002)
echo "Starting Worker 2 (GPU 1) on port 7002..."
APPTAINERENV_WORKER_GPU=cuda:1 apptainer exec --nv instance://chatapi /opt/chatbot-env/bin/uvicorn app.main:app \
  --host 127.0.0.1 \
  --port 7002 \
  --log-level warning &

WORKER2_PID=$!
echo $WORKER2_PID > .worker2.pid
echo "  → Worker 2 PID: $WORKER2_PID"

# Give second worker time to start
sleep 3

# Start Load Balancer on port 7000
echo "Starting Load Balancer on port 7000..."
apptainer exec --nv instance://chatapi /opt/chatbot-env/bin/python load_balancer.py &

LB_PID=$!
echo $LB_PID > .loadbalancer.pid
echo "  → Load Balancer PID: $LB_PID"

echo ""
echo "✓ Multi-GPU service with queueing started!"
echo ""
echo "Architecture:"
echo "  Client → Load Balancer (port 7000)"
echo "           ├─→ Worker 1 (GPU 0, port 7001)"
echo "           └─→ Worker 2 (GPU 1, port 7002)"
echo ""
echo "API Endpoints:"
echo "  • Query: http://localhost:7000/query/"
echo "  • Health: http://localhost:7000/health"
echo "  • Stats: http://localhost:7000/stats"
echo ""
echo "Features:"
echo "  • Accepts unlimited concurrent requests"
echo "  • Intelligent queue management"
echo "  • Automatic load balancing"
echo "  • ~24 tokens/sec total throughput"
echo ""
echo "To stop all services:"
echo "  ./stop_multi_gpu.sh"
echo ""
echo "Monitoring:"
echo "  watch -n 1 'curl -s http://localhost:7000/stats | jq'"
