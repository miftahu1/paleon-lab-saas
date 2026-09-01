const express = require('express');
const path = require('path');

const app = express();
const PORT = 3000;

// Serve the static HTML file
app.use(express.static(__dirname));

// Health check endpoint
app.get('/health', (req, res) => {
  res.json({
    status: 'ok',
    timestamp: new Date().toISOString(),
    uptime: process.uptime()
  });
});

// Root endpoint
app.get('/', (req, res) => {
  res.sendFile(path.join(__dirname, 'index.html'));
});

app.listen(PORT, () => {
  console.log(`SignalDesk dev server running on port ${PORT}`);
});
