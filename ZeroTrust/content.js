
// 创建Matrix数字雨
function createMatrixRain() {
  const canvas = document.createElement('canvas');
  canvas.id = 'matrix-canvas';
  canvas.width = window.innerWidth;
  canvas.height = window.innerHeight;
  document.body.appendChild(canvas);

  const ctx = canvas.getContext('2d');
  const fontSize = 16;
  const columns = canvas.width / fontSize;
  const drops = Array(Math.floor(columns)).fill(0);

  function draw() {
    ctx.fillStyle = 'rgba(0, 0, 0, 0.05)';
    ctx.fillRect(0, 0, canvas.width, canvas.height);
    ctx.fillStyle = '#0F0';
    ctx.font = `${fontSize}px monospace`;

    for (let i = 0; i < drops.length; i++) {
      const text = Math.random() > 0.5 ? '1' : '0';
      ctx.fillText(text, i * fontSize, drops[i] * fontSize);
      if (drops[i] * fontSize > canvas.height && Math.random() > 0.975) {
        drops[i] = 0;
      }
      drops[i]++;
    }
  }

  setInterval(draw, 33);
}

// 创建多个滚动骷髅
function createMultipleSkulls(count = 5) {
  const skulls = [];

  for (let i = 0; i < count; i++) {
    const skull = document.createElement('img');
    skull.src = 'https://172.16.1.20:8000/oiiaioooooiai.gif';
    skull.style.position = 'absolute';
    skull.style.width = '100px';
    skull.style.height = '100px';
    skull.style.zIndex = 10000;
    document.body.appendChild(skull);
    skulls.push(skull);
  }

  const animations = skulls.map(() => ({
    posX: Math.random() * window.innerWidth,
    posY: Math.random() * window.innerHeight,
    speedX: (Math.random() - 0.5) * 5,
    speedY: (Math.random() - 0.5) * 5
  }));

  function moveSkulls() {
    animations.forEach((anim, index) => {
      const skull = skulls[index];
      anim.posX += anim.speedX;
      anim.posY += anim.speedY;

      // 边界反弹或重新定位
      if (anim.posX < 0 || anim.posX > window.innerWidth) anim.speedX = -anim.speedX;
      if (anim.posY < 0 || anim.posY > window.innerHeight) {
        anim.posY = -100; // 从顶部重新出现
        anim.posX = Math.random() * window.innerWidth;
      }

      skull.style.left = `${anim.posX}px`;
      skull.style.top = `${anim.posY}px`;
    });

    requestAnimationFrame(moveSkulls);
  }

  moveSkulls();
}

// 创建警告文字
function createWarningText() {
  const warning = document.createElement('div');
  warning.id = 'warning-text';
  warning.textContent = '您的浏览器已被OIIAOIIA控制';
  document.body.appendChild(warning);
}

// 初始化
window.addEventListener('load', () => {
  createMatrixRain();
  createMultipleSkulls(); 
  createWarningText();
});

// 调整窗口大小时更新
window.addEventListener('resize', () => {
  const canvas = document.getElementById('matrix-canvas');
  if (canvas) {
    canvas.width = window.innerWidth;
    canvas.height = window.innerHeight;
  }
});