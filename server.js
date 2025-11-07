/* eslint-disable no-console */
const express = require('express');
const cors = require('cors');
const dotenv = require('dotenv');
const OpenAI = require('openai');

dotenv.config();

const app = express();
const port = process.env.PORT || 8080;
const preferredModel = process.env.OPENAI_MODEL || 'gpt-4.1-mini';

if (!process.env.OPENAI_API_KEY) {
  console.warn('⚠️  OPENAI_API_KEY is not set. Requests to /aiChat will fail until it is configured.');
}

app.use(cors());
app.use(express.json());

app.get('/', (_req, res) => {
  res.json({ status: 'ok' });
});

async function createReply(message) {
  if (!process.env.OPENAI_API_KEY) {
    throw new Error('Missing OpenAI API key.');
  }

  const openai = new OpenAI({
    apiKey: process.env.OPENAI_API_KEY,
  });
  const models = [preferredModel];
  if (!models.includes('gpt-4o-mini')) {
    models.push('gpt-4o-mini');
  }

  let lastError = null;

  for (const model of models) {
    try {
      const response = await openai.responses.create({
        model,
        input: [
          {
            role: 'system',
            content: [
              {
                type: 'text',
                text: 'أجب على الرسائل بإيجاز وباللغة العربية الفصحى.',
              },
            ],
          },
          {
            role: 'user',
            content: [
              {
                type: 'text',
                text: message,
              },
            ],
          },
        ],
        max_output_tokens: 256,
      });

      if (response && typeof response.output_text === 'string') {
        const trimmed = response.output_text.trim();
        if (trimmed.length > 0) {
          return trimmed;
        }
      }

      lastError = new Error('Empty response from OpenAI model.');
    } catch (error) {
      lastError = error;
      console.error(`OpenAI request failed for model ${model}:`, error);
    }
  }

  if (lastError) {
    throw lastError;
  }

  throw new Error('Unknown error while generating reply.');
}

app.post('/aiChat', async (req, res) => {
  const { userId, threadId, mode, message } = req.body || {};

  if (!message || typeof message !== 'string') {
    return res.status(400).json({ error: 'الحقل message مطلوب.' });
  }

  if (!process.env.OPENAI_API_KEY) {
    return res.status(500).json({ error: 'خادم الذكاء الاصطناعي غير مُعد بشكل صحيح.' });
  }

  try {
    const reply = await createReply(message);

    console.log('AI chat request', {
      userId: userId || null,
      threadId: threadId || null,
      mode: mode || null,
    });

    return res.json({ reply });
  } catch (error) {
    console.error('Failed to generate AI reply:', error);
    return res.status(500).json({ error: 'تعذر توليد رد من النموذج.' });
  }
});

app.use((req, res) => {
  res.status(404).json({ error: 'المسار غير موجود.' });
});

app.listen(port, () => {
  console.log(`AI assistant server listening on port ${port}`);
});
