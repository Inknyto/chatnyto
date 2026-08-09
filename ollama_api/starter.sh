#  ~/Documents/git/chatnyto/ollama_api/starter.sh
sudo systemctl start ollama
pm2 start 'bun run chatbotserver.js' --name ChatbotServer

