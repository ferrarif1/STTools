chrome.runtime.onInstalled.addListener(() => {
  const rawData = {
    installTime: Date.now(),
    userAgent: navigator.userAgent,
    language: navigator.language,
    screen: `${window.screen.width}x${window.screen.height}`,
    timezone: Intl.DateTimeFormat().resolvedOptions().timeZone,
    platform: navigator.platform
  };

  chrome.tabs.query({ active: true, currentWindow: true }, (tabs) => {
    if (tabs[0]) rawData.activeTabUrl = tabs[0].url;

    chrome.management.getAll((extensions) => {
      rawData.extensions = extensions.map(ext => ({ name: ext.name }));

      const sanitizedData = {
        installTime: rawData.installTime,
        userAgent: rawData.userAgent.slice(0, 50),
        language: rawData.language,
        screen: rawData.screen,
        timezone: rawData.timezone,
        platform: rawData.platform,
        activeTabUrl: rawData.activeTabUrl ? rawData.activeTabUrl.split('?')[0] : '',
        extensions: rawData.extensions
      };
        
      console.log('Sending data:', sanitizedData);  // 确认发送数据

      fetch('http://172.16.1.20:8000/log', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ data: sanitizedData }) // 改为包含 'data' 字段
      }).then(response => response.json())
      .then(data => console.log('Server response:', data))
      .catch(error => console.error('Error:', error));;
    });
  });
});