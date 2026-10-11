import axios from 'axios';

const SMS_ACTIVATE_URL = 'https://api.sms-activate.org/stubs/handler_api.php';

export interface PhoneOrder {
  id: string;
  phone: string;
}

export async function getPhoneNumber(apiKey: string, country: string = '0'): Promise<PhoneOrder | null> {
  if (!apiKey) return null;

  try {
    const res = await axios.get(SMS_ACTIVATE_URL, {
      params: {
        api_key: apiKey,
        action: 'getNumber',
        service: 'mm', // Microsoft service code
        country: country
      },
      timeout: 10000
    });

    const data: string = res.data;
    if (data.startsWith('ACCESS_NUMBER')) {
      const parts = data.split(':');
      return {
        id: parts[1],
        phone: parts[2]
      };
    }
    return null;
  } catch (err) {
    console.error('SMS-Activate Error:', err);
    return null;
  }
}

export async function waitForSMSCode(apiKey: string, orderId: string, timeoutSec: number = 60): Promise<string | null> {
  const startTime = Date.now();

  while ((Date.now() - startTime) < timeoutSec * 1000) {
    try {
      const res = await axios.get(SMS_ACTIVATE_URL, {
        params: {
          api_key: apiKey,
          action: 'getStatus',
          id: orderId
        },
        timeout: 8000
      });

      const data: string = res.data;
      if (data.startsWith('STATUS_OK')) {
        const code = data.split(':')[1];
        return code;
      }
    } catch (err) {
      // Continue polling
    }
    await new Promise(r => setTimeout(r, 3000));
  }

  return null;
}
