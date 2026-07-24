#!/bin/bash
set -euo pipefail

echo "=== Setting up Supabase client and edge functions ==="

SUPABASE_URL="https://olhtxibbyhucxcmhzblq.supabase.co"
SUPABASE_ANON_KEY="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9saHR4aWJieWh1Y3hjbWh6YmxxIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQ4NTM3NzAsImV4cCI6MjEwMDQyOTc3MH0.hRzU2t44sDBqGmRiRhlxxH1Q1bfdSgV8yN_jm5HWO1Y"
SUPABASE_SERVICE_KEY="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9saHR4aWJieWh1Y3hjbWh6YmxxIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc4NDg1Mzc3MCwiZXhwIjoyMTAwNDI5NzcwfQ.rz3vITWn504AhSdS52mbGvuOTxBpnAq0dUz7YrgcTsw"
SUPABASE_DB_PASSWORD="3d9608e21e5e4ac511d0f803860098d4"

# Install Supabase CLI
if ! command -v supabase &>/dev/null; then
    echo "Installing Supabase CLI..."
    curl -fsSL https://supabase.com/install.sh | bash
fi

# Initialize Supabase project in the repo
if [ ! -f "supabase/config.toml" ]; then
    supabase init --project-ref olhtxibbyhucxcmhzblq
fi

# Set Supabase credentials as GitHub secrets documentation
cat > .supabase.env << EOF
SUPABASE_URL=${SUPABASE_URL}
SUPABASE_ANON_KEY=${SUPABASE_ANON_KEY}
SUPABASE_SERVICE_KEY=${SUPABASE_SERVICE_KEY}
SUPABASE_DB_PASSWORD=${SUPABASE_DB_PASSWORD}
EOF

echo "Supabase credentials saved to .supabase.env (add to .gitignore)"

echo "=== Supabase setup complete ==="