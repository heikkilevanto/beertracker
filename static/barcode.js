// barcode.js
// Barcode scanning module for BeerTracker
// Supports camera-based barcode scanning into input fields

(function() {
  'use strict';

  // Global state
  let activeStream = null;
  let activeScanner = null;
  let targetInput = null;
  let scannerOverlay = null;

  // Initialize barcode scanning for an input field
  // Adds a camera icon button next to the input that opens the scanner
  window.initBarcodeInput = function(inputId) {
    const input = document.getElementById(inputId);
    if (!input) {
      console.error('Input field not found:', inputId);
      return;
    }

    // Create scan button
    const scanBtn = document.createElement('button');
    scanBtn.type = 'button';
    scanBtn.className = 'barcode-scan-btn';
    scanBtn.innerHTML = '📷';
    scanBtn.title = 'Scan barcode';
    scanBtn.style.cssText = 'margin-left: 5px; padding: 5px 10px; cursor: pointer;';
    
    scanBtn.addEventListener('click', function(e) {
      e.preventDefault();
      startScanning(input);
    });

    // Insert button after input
    input.parentNode.insertBefore(scanBtn, input.nextSibling);
  };

  // Start the barcode scanner (by input element)
  function startScanning(input) {
    if (activeStream) {
      console.log('Scanner already active');
      return;
    }

    targetInput = input;
    createScannerOverlay();
    
    // Try to use native Barcode Detection API first, fallback to QuaggaJS
    if ('BarcodeDetector' in window) {
      startNativeScanning();
    } else {
      startQuaggaScanning();
    }
  }

  // Create the scanner overlay UI
  function createScannerOverlay() {
    scannerOverlay = document.createElement('div');
    scannerOverlay.id = 'barcode-scanner-overlay';
    scannerOverlay.style.cssText = `
      position: fixed;
      top: 0;
      left: 0;
      width: 100%;
      height: 100%;
      background: rgba(0, 0, 0, 0.9);
      z-index: 10000;
      display: flex;
      flex-direction: column;
      align-items: center;
      justify-content: center;
    `;

    const container = document.createElement('div');
    container.style.cssText = `
      max-width: 640px;
      width: 90%;
      text-align: center;
    `;

    const title = document.createElement('div');
    title.textContent = 'Scan Barcode';
    title.style.cssText = `
      color: white;
      font-size: 20px;
      margin-bottom: 10px;
      font-weight: bold;
    `;

    const videoContainer = document.createElement('div');
    videoContainer.style.cssText = `
      position: relative;
      background: black;
      margin: 10px auto;
    `;

    const video = document.createElement('video');
    video.id = 'barcode-video';
    video.autoplay = true;
    video.playsInline = true;
    video.style.cssText = `
      width: 100%;
      max-width: 640px;
      height: auto;
    `;

    const scanLine = document.createElement('div');
    scanLine.className = 'scan-line';
    scanLine.style.cssText = `
      position: absolute;
      top: 50%;
      left: 10%;
      right: 10%;
      height: 2px;
      background: #00ff00;
      box-shadow: 0 0 10px #00ff00;
      animation: scan 2s ease-in-out infinite;
    `;

    const status = document.createElement('div');
    status.id = 'barcode-status';
    status.textContent = 'Position barcode in view';
    status.style.cssText = `
      color: #00ff00;
      margin: 10px 0;
      font-size: 16px;
    `;

    const manualInput = document.createElement('div');
    manualInput.style.cssText = `
      margin: 15px 0;
    `;
    const manualField = document.createElement('input');
    manualField.type = 'text';
    manualField.id = 'manual-barcode';
    manualField.placeholder = 'Or type barcode manually';
    manualField.style.cssText = `
      padding: 8px;
      width: 70%;
      font-size: 16px;
    `;
    manualField.addEventListener('keypress', function(e) {
      if (e.key === 'Enter') {
        processBarcodeResult(this.value);
      }
    });

    const closeBtn = document.createElement('button');
    closeBtn.textContent = 'Close';
    closeBtn.style.cssText = `
      padding: 10px 30px;
      font-size: 16px;
      cursor: pointer;
      background: #666;
      color: white;
      border: none;
      border-radius: 5px;
      margin-top: 10px;
    `;
    closeBtn.addEventListener('click', stopScanning);

    // Add CSS animation
    const style = document.createElement('style');
    style.textContent = `
      @keyframes scan {
        0%, 100% { top: 20%; }
        50% { top: 80%; }
      }
    `;
    document.head.appendChild(style);

    videoContainer.appendChild(video);
    videoContainer.appendChild(scanLine);
    manualInput.appendChild(manualField);
    container.appendChild(title);
    container.appendChild(videoContainer);
    container.appendChild(status);
    container.appendChild(manualInput);
    container.appendChild(closeBtn);
    scannerOverlay.appendChild(container);
    document.body.appendChild(scannerOverlay);

    // Start camera
    startCamera();
  }

  // Start camera stream
  function startCamera() {
    navigator.mediaDevices.getUserMedia({
      video: {
        facingMode: 'environment', // Use rear camera on mobile
        width: { ideal: 1280 },
        height: { ideal: 720 }
      }
    })
    .then(function(stream) {
      activeStream = stream;
      const video = document.getElementById('barcode-video');
      video.srcObject = stream;
      updateStatus('Camera ready - scanning...', '#00ff00');
    })
    .catch(function(err) {
      console.error('Camera error:', err);
      updateStatus('Camera access denied. Please use manual input.', '#ff0000');
    });
  }

  // Start scanning using native Barcode Detection API
  function startNativeScanning() {
    const video = document.getElementById('barcode-video');
    const barcodeDetector = new BarcodeDetector({
      formats: ['ean_13', 'ean_8', 'upc_a', 'upc_e', 'code_128', 'code_39', 'qr_code']
    });

    let scanning = true;
    activeScanner = { stop: () => { scanning = false; } };

    function detectBarcode() {
      if (!scanning || !video.videoWidth) {
        if (scanning) requestAnimationFrame(detectBarcode);
        return;
      }

      barcodeDetector.detect(video)
        .then(barcodes => {
          if (barcodes.length > 0) {
            const barcode = barcodes[0];
            processBarcodeResult(barcode.rawValue);
          } else if (scanning) {
            requestAnimationFrame(detectBarcode);
          }
        })
        .catch(err => {
          console.error('Detection error:', err);
          if (scanning) requestAnimationFrame(detectBarcode);
        });
    }

    video.addEventListener('loadedmetadata', () => {
      detectBarcode();
    });
  }

  // Start scanning using QuaggaJS (fallback)
  function startQuaggaScanning() {
    // Check if Quagga is loaded
    if (typeof Quagga === 'undefined') {
      updateStatus('Barcode scanner not available. Please use manual input.', '#ff9900');
      console.warn('QuaggaJS not loaded. Include quagga.min.js for older browser support.');
      return;
    }

    Quagga.init({
      inputStream: {
        name: 'Live',
        type: 'LiveStream',
        target: document.querySelector('#barcode-video').parentNode,
        constraints: {
          facingMode: 'environment'
        }
      },
      decoder: {
        readers: ['ean_reader', 'ean_8_reader', 'code_128_reader', 'code_39_reader', 'upc_reader', 'upc_e_reader']
      }
    }, function(err) {
      if (err) {
        console.error('Quagga init error:', err);
        updateStatus('Scanner initialization failed. Please use manual input.', '#ff0000');
        return;
      }
      Quagga.start();
      activeScanner = Quagga;
    });

    Quagga.onDetected(function(result) {
      const code = result.codeResult.code;
      processBarcodeResult(code);
    });
  }

  // Process the scanned barcode
  function processBarcodeResult(code) {
    if (!code || !targetInput) return;

    // Clean up the code (remove non-digit characters for numeric barcodes)
    const cleanCode = code.trim();
    
    updateStatus('Barcode detected: ' + cleanCode, '#00ff00');
    
    // Fill the target input
    targetInput.value = cleanCode;
    
    // Trigger change event
    const event = new Event('input', { bubbles: true });
    targetInput.dispatchEvent(event);

    // Show success briefly then close
    setTimeout(function() {
      stopScanning();
    }, 800);
  }

  // Update status message
  function updateStatus(message, color) {
    const status = document.getElementById('barcode-status');
    if (status) {
      status.textContent = message;
      status.style.color = color || '#00ff00';
    }
  }

  // Stop scanning and clean up
  function stopScanning() {
    // Stop camera stream
    if (activeStream) {
      activeStream.getTracks().forEach(track => track.stop());
      activeStream = null;
    }

    // Stop scanner
    if (activeScanner) {
      if (activeScanner.stop && typeof activeScanner.stop === 'function') {
        try {
          activeScanner.stop();
        } catch (e) {
          console.log('Scanner stop error:', e);
        }
      }
      activeScanner = null;
    }

    // Remove overlay
    if (scannerOverlay) {
      scannerOverlay.remove();
      scannerOverlay = null;
    }

    targetInput = null;
  }

  // Allow attaching scanner to an existing button
  window.attachBarcodeScanner = function(buttonId, inputId) {
    const button = document.getElementById(buttonId);
    const input = document.getElementById(inputId);
    
    if (!button || !input) {
      console.error('Button or input not found:', buttonId, inputId);
      return;
    }

    button.addEventListener('click', function(e) {
      e.preventDefault();
      startScanning(input);
    });
  };

  // Utility: Check if barcode scanning is supported
  window.isBarcodeSupported = function() {
    return ('BarcodeDetector' in window) || (typeof Quagga !== 'undefined');
  };

  // Start scanning by field name (called from HTML onclick)
  window.startBarcodeScanning = function(fieldname) {
    const input = document.getElementById(fieldname);
    if (!input) {
      console.error('Barcode input field not found:', fieldname);
      return;
    }
    startScanning(input);
  };

})();
