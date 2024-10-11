import processing.sound.*;
import processing.video.*;
import gab.opencv.*;
import java.awt.Rectangle;

ArrayList<Agent> agents;
PVector flockCenter;
AudioIn mic;
Amplitude amp;
FFT fft;
Oscillator[] oscillators;
LowPass[] filters;
Env[] envelopes;
Reverb reverb;
Sound sound;
int numOscillators = 16;
boolean isInteracting = false;
float camX, camY, camZ;
float camZoom = 500;
float camRotX = PI/4, camRotY = -PI/4;
int soundInputDuration = 1000;
int[] majorScale = {0, 2, 4, 5, 7, 9, 11};
float baseFrequency = 261.63; // C4
int maxFaces = 10;
float[] oscillatorAmps;
float masterVolume = 1.0;
float targetMasterVolume = 1.0;
float globalCohesionFactor = 1.0;
float cohesionDecayRate = 0.98; // Changed from 0.99 to 0.98
float cohesionRecoveryRate = 1.02; // Changed from 1.01 to 1.02
int lastDetectedCount = 0;
float fadeValue = 0;
float fadeSpeed = 0.05;
boolean shouldPlaySound = false;

Capture video;
OpenCV opencv;
Rectangle[] people;
int lastPeopleCount = 0;
float interactionStrength = 0;

float[] detectionHistory = new float[10];
int detectionHistoryIndex = 0;

String staticText1 = "+ Ecosystem is evolving based on detected people.\n" +
  "+ Agents and music adapt to the number of people present.\n" +
  "+ Each person influences the system's behavior.\n" +
  "+ Observe how the ecosystem responds to changing inputs.";

String staticText2 = "+ Ecosystem awaits first detection to initialize.\n" +
  "+ Agents move randomly, anticipating input.\n" +
  "+ Introduce people to activate and shape the system.";

String staticText3 = "+ Ecosystem is losing complexity.\n" +
  "+ Agents and sounds reflect decreasing input.\n" +
  "+ System energy decreases as fewer people are detected.\n" +
  "+ Introduce more people to revitalize the ecosystem.";

PFont helveticaFont;
float alphaValue = 0;
float fadeInSpeed = 2;

int lastInteractionTime = 0;
int decayTime = 300000;
float systemEnergy = 0.0;

color[] colorPalette = {
  color(200, 150, 150),
  color(150, 200, 150),
  color(150, 150, 200),
  color(200, 200, 150),
  color(200, 150, 200),
  color(150, 200, 200)
};
color baseColor = color(200);
color targetColor = color(200);
color currentColor;

float[] lastInputSpectrum = new float[512];
long lastInputTime = 0;
int inputThreshold = 10000;

float[] oscillatorFrequencies;
float[] oscillatorAmplitudes;

float targetSystemEnergy = 0.0;
float energyLerpFactor = 0.05;

int rootNote = 60; // C4

float[][] flowField;
int cols, rows;
float flowFieldRes = 10;

ArrayList<Memory> memories = new ArrayList<Memory>();
int maxMemories = 300;
int memoryLifespan = 300000;

SinOsc ambientOsc;

float bpm = 60;
float beatInterval;
float lastBeatTime = 0;
int currentBeat = 0;

ResetButton resetButton;

LowPass masterLowPass;

// New variables for smooth activation
float[] oscillatorTargetAmps;
float ampSmoothFactor = 0.05;

void setup() {
  fullScreen(P3D);
  smooth(8);
  helveticaFont = createFont("Helvetica", 14);
  textFont(helveticaFont);

  agents = new ArrayList<Agent>();
  flockCenter = new PVector(width/2, height/2, 0);
  for (int i = 0; i < 1200; i++) {
    agents.add(new Agent());
  }

  video = new Capture(this, 320, 240);
  video.start();
  
  oscillatorAmps = new float[numOscillators];
  oscillatorTargetAmps = new float[numOscillators]; // Initialize new array
  for (int i = 0; i < numOscillators; i++) {
    oscillatorAmps[i] = 0;
    oscillatorTargetAmps[i] = 0; // Initialize target amplitudes
  }
  
  people = new Rectangle[0];

  opencv = new OpenCV(this, 320, 240);
  opencv.loadCascade(OpenCV.CASCADE_FRONTALFACE);  

  setupSound();

  cols = floor(width / flowFieldRes);
  rows = floor(height / flowFieldRes);
  flowField = new float[cols][rows];

  beatInterval = 60000 / bpm;

  currentColor = baseColor;

  resetButton = new ResetButton(width - 220, 20, 200, 50, "Reset to Initial State");

  updateSound();
}

void setupSound() {
  oscillators = new Oscillator[numOscillators];
  filters = new LowPass[numOscillators];
  envelopes = new Env[numOscillators];
  oscillatorFrequencies = new float[numOscillators];
  oscillatorAmplitudes = new float[numOscillators];
  sound = new Sound(this);
  reverb = new Reverb(this);

  println("Setting up sound...");

  for (int i = 0; i < numOscillators; i++) {
    oscillators[i] = new SinOsc(this);
    filters[i] = new LowPass(this);
    envelopes[i] = new Env(this);

    oscillators[i].play();
    oscillators[i].amp(0);  // Set initial amplitude to 0
    
    reverb.process(oscillators[i]);
    
    filters[i].process(oscillators[i]);
    
    filters[i].freq(2000);
    filters[i].res(0.5);
    
    int octave = i / majorScale.length;
    int scaleIndex = i % majorScale.length;
    oscillatorFrequencies[i] = baseFrequency * pow(2, (majorScale[scaleIndex] + octave * 12) / 12.0);
    oscillators[i].freq(oscillatorFrequencies[i]);
    
    println("Oscillator " + i + " setup complete. Frequency: " + oscillatorFrequencies[i]);
  }

  sound.volume(0);  // Set initial master volume to 0
  reverb.room(0.5);
  reverb.damp(0.6);
  reverb.wet(0.3);

  ambientOsc = new SinOsc(this);
  ambientOsc.freq(baseFrequency / 2);
  ambientOsc.amp(0);  // Set initial amplitude to 0
  ambientOsc.play();
  reverb.process(ambientOsc);

  masterLowPass = new LowPass(this);
  masterLowPass.freq(5000);
  masterLowPass.res(0.5);

  println("Sound setup complete.");
}

void draw() {
  background(0);
  drawFlowField();
  drawGrid();

  if (video.available()) {
    video.read();
  }

  opencv.loadImage(video);
  people = opencv.detect();

  updateSystem();

  updateCamera();

  updateFlockCenter();

  lights();

  for (Agent a : agents) {
    a.flock(agents);
    a.update();
    a.display();
  }

  drawConnections();

  camera();
  hint(DISABLE_DEPTH_TEST);
  noLights();
  drawStaticText();
  drawMemoryGraph();
  resetButton.display();
  drawWebcamAndDetection();
  hint(ENABLE_DEPTH_TEST);

  updateSound();
}

void updateSystem() {
  int currentPeopleCount = people.length;
  boolean peopleDetected = currentPeopleCount > 0;

  detectionHistory[detectionHistoryIndex] = currentPeopleCount;
  detectionHistoryIndex = (detectionHistoryIndex + 1) % detectionHistory.length;

  float averageDetection = 0;
  for (float count : detectionHistory) {
    averageDetection += count;
  }
  averageDetection /= detectionHistory.length;

  if (peopleDetected) {
    // Increase the rate of cohesion recovery
    globalCohesionFactor = min(globalCohesionFactor * cohesionRecoveryRate, 1.0);
    if (!isInteracting) {
      targetColor = colorPalette[int(random(colorPalette.length))];
      for (Agent a : agents) {
        a.velocity.mult(random(1.5, 2.0));
        a.maxSpeed *= 1.5;
        a.jitter = 0.5;
      }
    }
    lastInteractionTime = millis();
    isInteracting = true;
    updateMemory(currentPeopleCount);
    targetSystemEnergy = min(targetSystemEnergy + 0.02 * averageDetection, 1.0);

    lastPeopleCount = currentPeopleCount;
  } else {
    // Increase the rate of cohesion decay
    globalCohesionFactor *= cohesionDecayRate;
    isInteracting = false;
    targetSystemEnergy = max(targetSystemEnergy - 0.001, 0.0);
  }

  // Add a small amount of randomness to the cohesion factor for more dynamic behavior
  globalCohesionFactor += random(-0.01, 0.01);
  globalCohesionFactor = constrain(globalCohesionFactor, 0, 1);

  systemEnergy = lerp(systemEnergy, targetSystemEnergy, energyLerpFactor);
  currentColor = lerpColor(currentColor, targetColor, 0.05);

  float[] memoryState = calculateMemoryState();

  for (Agent a : agents) {
    a.adjustBehavior(systemEnergy, memoryState, currentPeopleCount);
    a.agentColor = currentColor;
  }

  updateFlowField(memoryState);
  updateRhythm(memoryState);

  for (int i = memories.size() - 1; i >= 0; i--) {
    Memory m = memories.get(i);
    m.update();
    if (millis() - m.timestamp > memoryLifespan) {
      if (!m.isDecaying) {
        m.startDecay();
      }
      if (m.decayProgress >= 1) {
        memories.remove(i);
      }
    }
  }

  println("People detected: " + peopleDetected);
  println("Current people count: " + currentPeopleCount);
  println("Global cohesion factor: " + globalCohesionFactor);
  println("System energy: " + systemEnergy);
  println("Memory count: " + memories.size());
}

void updateSound() {
  boolean faceDetected = (people != null && people.length > 0);
  
  // Update shouldPlaySound based on face detection
  if (faceDetected && !shouldPlaySound) {
    shouldPlaySound = true;
  } else if (!faceDetected && shouldPlaySound) {
    shouldPlaySound = false;
  }
  
  // Fade in/out logic
  if (shouldPlaySound && fadeValue < 1) {
    fadeValue += fadeSpeed;
  } else if (!shouldPlaySound && fadeValue > 0) {
    fadeValue -= fadeSpeed;
  }
  fadeValue = constrain(fadeValue, 0, 1);
  
  // If no sound should be played and fade out is complete, silence everything and return
  if (!shouldPlaySound && fadeValue == 0) {
    for (int i = 0; i < numOscillators; i++) {
      oscillators[i].amp(0);
      oscillatorAmplitudes[i] = 0;
      oscillatorTargetAmps[i] = 0;
    }
    ambientOsc.amp(0);
    sound.volume(0);
    return;
  }
  
  int faceCount = (people != null) ? min(people.length, maxFaces) : 0;
  println("Detected faces: " + faceCount);
  
  float complexityFactor = map(faceCount, 0, maxFaces, 0, 1);
  
  targetMasterVolume = map(faceCount, 0, maxFaces, 0.5, 1.0);
  masterVolume = lerp(masterVolume, targetMasterVolume, 0.05);
  
  float baseAmp = 0.2;
  
  for (int i = 0; i < numOscillators; i++) {
    float activationThreshold = map(i, 0, numOscillators - 1, 0, maxFaces);
    
    if (faceCount > activationThreshold) {
      float freqMod = map(noise(frameCount * 0.005 + i * 10), 0, 1, 0.995, 1.005);
      oscillators[i].freq(oscillatorFrequencies[i] * freqMod);
      
      float rhythmFactor = 0.5 + 0.5 * sin(TWO_PI * frameCount / (240 + i * 30));
      oscillatorTargetAmps[i] = baseAmp * rhythmFactor;
    } else {
      oscillatorTargetAmps[i] = 0;
    }
    
    // Smooth amplitude changes
    oscillatorAmplitudes[i] = lerp(oscillatorAmplitudes[i], oscillatorTargetAmps[i], ampSmoothFactor);
    
    // Apply fade value to the amplitude
    oscillators[i].amp(oscillatorAmplitudes[i] * masterVolume * fadeValue);
    
    float filterFreq = map(complexityFactor, 0, 1, 500, 2000);
    filters[i].freq(filterFreq);
  }
  
  reverb.room(map(faceCount, 0, maxFaces, 0.3, 0.6));
  reverb.damp(map(faceCount, 0, maxFaces, 0.7, 0.4));
  reverb.wet(map(faceCount, 0, maxFaces, 0.2, 0.4));
  
  float ambientFreq = baseFrequency / 2 * map(noise(frameCount * 0.0005), 0, 1, 0.995, 1.005);
  ambientOsc.freq(ambientFreq);
  float ambientAmp = map(complexityFactor, 0, 1, 0.05, 0.15) * masterVolume;
  // Apply fade value to the ambient oscillator amplitude
  ambientOsc.amp(ambientAmp * fadeValue);
  
  float masterFilterFreq = map(complexityFactor, 0, 1, 2000, 5000);
  masterLowPass.freq(masterFilterFreq);
  
  // Apply fade value to the master volume
  sound.volume(masterVolume * fadeValue);
  
  println("Master volume: " + (masterVolume * fadeValue));
}

void updateMemory(int peopleCount) {
  float normalizedCount = map(peopleCount, 1, 10, 0, 1);
  float duration = millis() - lastInteractionTime;

  memories.add(new Memory(normalizedCount, normalizedCount, duration));
  if (memories.size() > maxMemories) {
    memories.remove(0);
  }
}

float[] calculateMemoryState() {
  float[] state = new float[3];
  if (memories.size() == 0) return state;

  for (Memory m : memories) {
    state[0] += m.frequency;
    state[1] += m.amplitude;
    state[2] += m.duration;
  }

  for (int i = 0; i < 3; i++) {
    state[i] /= memories.size();
  }

  return state;
}

void updateCamera() {
  camX = width / 2 + camZoom * cos(camRotX) * cos(camRotY);
  camY = height / 2 + camZoom * sin(camRotX);
  camZ = (height / 2) + camZoom * cos(camRotX) * sin(camRotY);
  camera(camX, camY, camZ, width / 2, height / 2, 0, 0, 1, 0);
}

void updateFlockCenter() {
  flockCenter.x = noise(frameCount * 0.005) * width;
  flockCenter.y = noise(frameCount * 0.005 + 1000) * height;
  flockCenter.z = noise(frameCount * 0.005 + 2000) * (height / 2);
}

void updateRhythm(float[] memoryState) {
  float currentTime = millis();
  if (currentTime - lastBeatTime >= beatInterval) {
    currentBeat = (currentBeat + 1) % 4;
    lastBeatTime = currentTime;

    bpm = map(memoryState[1], 0, 1, 60, 120);
    bpm = constrain(bpm, 60, 120);
    beatInterval = 60000 / bpm;
  }
}

void updateFlowField(float[] memoryState) {
  float noiseScale = map(memoryState[2], 0, 1, 0.05, 0.2);
  for (int i = 0; i < cols; i++) {
    for (int j = 0; j < rows; j++) {
      float angle = noise(i * noiseScale, j * noiseScale, frameCount * 0.01) * TWO_PI * 4;
      angle += map(memoryState[0], 0, 1, -PI/4, PI/4);
      flowField[i][j] = angle;
    }
  }
}

void drawFlowField() {
  stroke(currentColor, 40);  // Reduced opacity from 30 to 15
  pushMatrix();
  for (int i = 0; i < cols; i++) {
    for (int j = 0; j < rows; j++) {
      pushMatrix();
      translate(i * flowFieldRes, j * flowFieldRes);
      rotate(flowField[i][j]);
      line(0, 0, flowFieldRes, 0);
      popMatrix();
    }
  }
  popMatrix();
}

void drawConnections() {
  stroke(currentColor, 50);
  for (int i = 0; i < agents.size(); i++) {
    Agent a1 = agents.get(i);
    for (int j = i + 1; j < agents.size(); j++) {
      Agent a2 = agents.get(j);
      float d = PVector.dist(a1.position, a2.position);
      if (d < 50 * systemEnergy) {
        line(a1.position.x, a1.position.y, a1.position.z, 
             a2.position.x, a2.position.y, a2.position.z);
      }
    }
  }
}

void drawMemoryGraph() {
  int graphWidth = width / 3;
  int graphHeight = 100;
  int graphX = 20;
  int graphY = height - graphHeight - 20;

  fill(0, 100);
  rect(graphX, graphY, graphWidth, graphHeight);

  noFill();
  beginShape();
  for (int i = 0; i < memories.size(); i++) {
    Memory m = memories.get(i);
    float x = map(i, 0, memories.size() - 1, graphX, graphX + graphWidth);
    float y = map(m.frequency, 0, 1, graphY + graphHeight * 0.75, graphY + graphHeight * 0.25);
    if (!m.isDecaying) {
      stroke(currentColor);
      vertex(x, y);
    }
  }
  endShape();

  for (int i = 0; i < memories.size(); i++) {
    Memory m = memories.get(i);
    float x = map(i, 0, memories.size() - 1, graphX, graphX + graphWidth);
    float y = map(m.frequency, 0, 1, graphY + graphHeight * 0.75, graphY + graphHeight * 0.25);
    if (m.isDecaying) {
      stroke(currentColor, 255 * (1 - m.decayProgress));
      for (PVector p : m.particles) {
        float px = x + p.x * m.decayProgress;
        float py = y + p.y * m.decayProgress;
        point(px, py);
      }
    }
  }

  stroke(currentColor, 50);
  line(graphX, graphY + graphHeight / 2, graphX + graphWidth, graphY + graphHeight / 2);

  noFill();
  stroke(currentColor);
  rect(graphX, graphY, graphWidth, graphHeight);

  fill(currentColor);
  textAlign(LEFT, BOTTOM);
  textSize(14);
  text("People Detected: " + people.length, graphX, graphY - 5);
}

void drawStaticText() {
  fill(currentColor, alphaValue);
  textSize(14);
  textAlign(LEFT, TOP);

  int textWidth = width - 40;
  int textHeight = 80;
  int x = 20;
  int y = 20;

  if (isInteracting || systemEnergy > 0.5) {
    text(staticText1, x, y, textWidth, textHeight);
  } else if (memories.size() == 0) {
    text(staticText2, x, y, textWidth, textHeight);
  } else {
    text(staticText3, x, y, textWidth, textHeight);
  }

  if (alphaValue < 255) {
    alphaValue += fadeInSpeed;
    alphaValue = constrain(alphaValue, 0, 255);
  }
}

void drawGrid() {
  stroke(currentColor, 30);
  int gridSize = 20;
  for (int i = 0; i < width; i += gridSize) {
    line(i, 0, i, height);
  }
  for (int j = 0; j < height; j += gridSize) {
    line(0, j, width, j);
  }
}

void drawWebcamAndDetection() {
  int camWidth = 160;
  int camHeight = 120;
  int camX = width - camWidth - 20;
  int camY = height - camHeight - 20;

  pushStyle();
  strokeWeight(1);
  stroke(currentColor);
  noFill();
  
  rect(camX - 3, camY - 3, camWidth + 6, camHeight + 6);
  
  for (int i = 0; i < 2; i++) {
    stroke(currentColor, 80 - i * 40);
    rect(camX - i, camY - i, camWidth + i * 2, camHeight + i * 2);
  }
  
  pushMatrix();
  translate(camX + camWidth, camY);
  scale(-1, 1);
  image(video, 0, 0, camWidth, camHeight);
  popMatrix();
  
  noFill();
  strokeWeight(2);
  for (Rectangle face : people) {
    float scaleFactor = (float)camWidth / video.width;
    
    float rectX = camX + (video.width - face.x - face.width) * scaleFactor;
    float rectY = camY + face.y * scaleFactor;
    float rectWidth = face.width * scaleFactor;
    float rectHeight = face.height * scaleFactor;
    
    stroke(red(currentColor), green(currentColor), blue(currentColor), 200);
    rect(rectX, rectY, rectWidth, rectHeight);
    
    strokeWeight(1);
    for (int i = 1; i <= 2; i++) {
      stroke(red(currentColor), green(currentColor), blue(currentColor), 40 - i * 15);
      rect(rectX - i, rectY - i, rectWidth + i * 2, rectHeight + i * 2);
    }
  }
  
  popStyle();
}

void mouseDragged() {
  float sensitivity = 0.01;
  camRotY += (pmouseX - mouseX) * sensitivity;
  camRotX += (pmouseY - mouseY) * sensitivity;
  camRotX = constrain(camRotX, -PI/2, PI/2);
}

void mouseWheel(MouseEvent event) {
  float e = event.getCount();
  camZoom += e * 40;
  camZoom = constrain(camZoom, 50, 5000);
}

void mousePressed() {
  if (resetButton.isMouseOver()) {
    resetSystem();
  }
}

void mouseMoved() {
  resetButton.checkHover(mouseX, mouseY);
}

void resetSystem() {
  memories.clear();
  systemEnergy = 0;
  targetSystemEnergy = 0;
  currentColor = baseColor;
  targetColor = baseColor;

  for (Agent a : agents) {
    a.position = new PVector(random(width), random(height), random(-height/2, height/2));
    a.velocity = PVector.random3D().mult(4);
    a.acceleration = new PVector(0, 0);
    a.maxSpeed = 4;
    a.maxForce = 0.2;
    a.agentColor = currentColor;
    a.separationWeight = 3.0;
    a.alignmentWeight = 0.3;
    a.cohesionWeight = 0.1;
    a.centerWeight = 0.05;
    a.jitter = 0;
  }

  for (int i = 0; i < numOscillators; i++) {
    oscillators[i].amp(0);
    oscillatorAmplitudes[i] = 0;
    oscillatorTargetAmps[i] = 0;
  }

  lastInteractionTime = 0;
  isInteracting = false;

  camZoom = 500;
  camRotX = PI/4;
  camRotY = -PI/4;

  for (int i = 0; i < cols; i++) {
    for (int j = 0; j < rows; j++) {
      flowField[i][j] = 0;
    }
  }
}

class ResetButton {
  float x, y, w, h;
  String label;
  boolean isHovered;
  final float PADDING = 20;

  ResetButton(float x, float y, float w, float h, String label) {
    this.x = x;
    this.y = y;
    this.w = w;
    this.h = h;
    this.label = label;
    this.isHovered = false;
  }

  void display() {
    pushStyle();
    
    textSize(14);
    float textWidth = textWidth(label);
    w = textWidth + 20;
    h = 25;
    
    x = width - w - PADDING;
    
    color bgColor = color(red(currentColor), green(currentColor), blue(currentColor), 50);
    if (isHovered) {
      for (int i = 0; i < 5; i++) {
        float alpha = lerp(30, 0, i / 5.0);
        fill(currentColor, alpha);
        noStroke();
        rect(x - i, y - i, w + i*2, h + i*2, h/2);
      }
      bgColor = color(red(currentColor), green(currentColor), blue(currentColor), 80);
    }
    
    fill(bgColor);
    stroke(currentColor);
    strokeWeight(1);
    rect(x, y, w, h, h/2);
    
    fill(currentColor);
    textAlign(CENTER, CENTER);
    textSize(14);
    text(label, x + w/2, y + h/2);
    
    popStyle();
  }

  boolean isMouseOver() {
    return mouseX > x && mouseX < x + w && mouseY > y && mouseY < y + h;
  }

  void checkHover(float mx, float my) {
    isHovered = mx > x && mx < x + w && my > y && my < y + h;
  }
}

class Agent {
  PVector position;
  PVector velocity;
  PVector acceleration;
  float maxForce;
  float maxSpeed;
  color agentColor;
  float separationWeight;
  float alignmentWeight;
  float cohesionWeight;
  float centerWeight;
  int oscillatorIndex;
  float size;
  float jitter;

  Agent() {
    position = new PVector(random(width), random(height), random(-height/2, height/2));
    velocity = PVector.random3D().mult(4);
    acceleration = new PVector(0, 0);
    maxSpeed = 4;
    maxForce = 0.2;
    agentColor = currentColor;
    separationWeight = 3.0;
    alignmentWeight = 0.3;
    cohesionWeight = 0.1;
    centerWeight = 0.05;
    oscillatorIndex = floor(random(numOscillators));
    size = 5;
    jitter = 0;
  }

  void adjustBehavior(float energy, float[] memoryState, int peopleCount) {
    float baseSeparation = 1.5;
    float baseAlignment = 1.0;
    float baseCohesion = 1.0;

    float memoryFactor = map(memories.size(), 0, maxMemories, 0, 1);
    float cohesionFactor = map(constrain(peopleCount, 0, 10), 0, 10, 0, 1);

    separationWeight = lerp(baseSeparation * 2, baseSeparation, memoryFactor * energy * globalCohesionFactor);
    alignmentWeight = lerp(0.1, baseAlignment, memoryFactor * energy * globalCohesionFactor * cohesionFactor);
    cohesionWeight = lerp(0.05, baseCohesion, memoryFactor * energy * globalCohesionFactor * cohesionFactor);

    centerWeight = map(energy, 0, 1, 0.05, 0.8) * cohesionFactor * globalCohesionFactor;

    maxSpeed = lerp(6, map(memoryState[1], 0, 1, 2, 6), globalCohesionFactor);
    maxForce = lerp(0.1, map(memoryState[2], 0, 1, 0.1, 0.25), globalCohesionFactor);

    jitter = lerp(1.0, 0, globalCohesionFactor) * energy;
  }

  void update() {
    PVector random = PVector.random3D();
    random.mult(map(1 - globalCohesionFactor, 0, 1, 0.2, 1.0));
    applyForce(random);

    int col = constrain(floor(position.x / flowFieldRes), 0, cols - 1);
    int row = constrain(floor(position.y / flowFieldRes), 0, rows - 1);
    PVector flowForce = PVector.fromAngle(flowField[col][row]);
    flowForce.mult(0.1 * globalCohesionFactor);
    applyForce(flowForce);

    PVector verticalForce = new PVector(0, 0, random(-1, 1) * cohesionWeight * globalCohesionFactor);
    applyForce(verticalForce);

    PVector jitterForce = PVector.random3D().mult(jitter);
    applyForce(jitterForce);

    velocity.add(acceleration);
    velocity.limit(maxSpeed);
    position.add(velocity);
    acceleration.mult(0);
    edges();
  }

  void edges() {
    if (position.x > width) position.x = 0;
    if (position.x < 0) position.x = width;
    if (position.y > height) position.y = 0;
    if (position.y < 0) position.y = height;
    if (position.z > height/2) position.z = -height/2;
    if (position.z < -height/2) position.z = height/2;
  }

  void applyForce(PVector force) {
    acceleration.add(force);
  }

  void flock(ArrayList<Agent> agents) {
    PVector sep = separate(agents);
    PVector ali = align(agents);
    PVector coh = cohesion(agents);
    PVector cent = seekCenter(flockCenter);

    sep.mult(separationWeight);
    ali.mult(alignmentWeight);
    coh.mult(cohesionWeight);
    cent.mult(centerWeight);
    applyForce(sep);
    applyForce(ali);
    applyForce(coh);
    applyForce(cent);
  }

  void display() {
    noStroke();
    pushMatrix();
    translate(position.x, position.y, position.z);
    float theta = velocity.heading() + PI/2;
    rotateZ(theta);
    rotateY(PI/2);

    float ambient = 0.7;
    float diffuse = 0.3;
    PVector lightDir = new PVector(0, -1, -1).normalize();
    float shading = ambient + diffuse * max(0, -PVector.dot(velocity.normalize(), lightDir));
    color shadedColor = lerpColor(color(0), agentColor, shading);

    fill(shadedColor);

    beginShape();
    vertex(0, -size, 0);
    vertex(-size/2, size/2, 0);
    vertex(size/2, size/2, 0);
    endShape(CLOSE);

    fill(lerpColor(shadedColor, color(255), 0.1));
    beginShape();
    vertex(0, -size, 0);
    vertex(-size*2, -size/2, size*0.75);
    vertex(-size*2, -size/2, -size*0.75);
    endShape(CLOSE);
    beginShape();
    vertex(0, -size, 0);
    vertex(size*2, -size/2, size*0.75);
    vertex(size*2, -size/2, -size*0.75);
    endShape(CLOSE);

    float glowSize = size * 1.5;
    fill(lerpColor(shadedColor, color(255), 0.3), 50);
    ellipse(0, 0, glowSize, glowSize);

    popMatrix();
  }

  PVector separate(ArrayList<Agent> agents) {
    float desiredSeparation = 25;
    PVector sum = new PVector();
    int count = 0;
    for (Agent other : agents) {
      float d = PVector.dist(position, other.position);
      if (d > 0 && d < desiredSeparation) {
        PVector diff = PVector.sub(position, other.position);
        diff.normalize();
        diff.div(d);
        sum.add(diff);
        count++;
      }
    }
    if (count > 0) {
      sum.div(count);
      sum.setMag(maxSpeed);
      sum.sub(velocity);
      sum.limit(maxForce);
    }
    return sum;
  }

  PVector align(ArrayList<Agent> agents) {
    float neighborDist = 50;
    PVector sum = new PVector();
    int count = 0;
    for (Agent other : agents) {
      float d = PVector.dist(position, other.position);
      if (d > 0 && d < neighborDist) {
        sum.add(other.velocity);
        count++;
      }
    }
    if (count > 0) {
      sum.div(count);
      sum.setMag(maxSpeed);
      PVector steer = PVector.sub(sum, velocity);
      steer.limit(maxForce);
      return steer;
    } else {
      return new PVector();
    }
  }

  PVector cohesion(ArrayList<Agent> agents) {
    float neighborDist = 50;
    PVector sum = new PVector();
    int count = 0;
    for (Agent other : agents) {
      float d = PVector.dist(position, other.position);
      if (d > 0 && d < neighborDist) {
        sum.add(other.position);
        count++;
      }
    }
    if (count > 0) {
      sum.div(count);
      return seek(sum);
    } else {
      return new PVector();
    }
  }

  PVector seekCenter(PVector target) {
    PVector desired = PVector.sub(target, position);
    desired.setMag(maxSpeed);
    PVector steer = PVector.sub(desired, velocity);
    steer.limit(maxForce);
    return steer;
  }

  PVector seek(PVector target) {
    PVector desired = PVector.sub(target, position);
    desired.setMag(maxSpeed);
    PVector steer = PVector.sub(desired, velocity);
    steer.limit(maxForce);
    return steer;
  }
}

class Memory {
  float frequency;
  float amplitude;
  float duration;
  int timestamp;
  boolean isDecaying;
  float decayProgress;
  PVector position;
  ArrayList<PVector> particles;

  Memory(float f, float a, float d) {
    frequency = f;
    amplitude = a;
    duration = d;
    timestamp = millis();
    isDecaying = false;
    decayProgress = 0;
    position = new PVector(random(width), random(height));
    particles = new ArrayList<PVector>();
  }

  void startDecay() {
    isDecaying = true;
    for (int i = 0; i < 20; i++) {
      particles.add(new PVector(random(-5, 5), random(-5, 5)));
    }
  }

  void update() {
    if (isDecaying) {
      decayProgress += 0.02;
      for (PVector p : particles) {
        p.mult(1.05);
      }
    }
  }
}

float midiToFreq(int note) {
  return 440 * pow(2, (note - 69) / 12.0);
}
