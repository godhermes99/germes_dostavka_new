<<<<<<< HEAD
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  // Обробка CORS для Flutter
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const { order_id, amount } = await req.json()
    
    // Беремо секретний токен Monobank із захищених змінних середовища Supabase
    const monoToken = Deno.env.get('MONOBANK_TOKEN')

    if (!monoToken) {
      throw new Error('Токен Monobank не налаштовано на сервері')
    }

    // Звертаємося до API Monobank
    const response = await fetch('https://api.monobank.ua/api/merchant/invoice/create', {
      method: 'POST',
      headers: {
        'X-Token': monoToken,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({
        amount: Math.round(amount * 100), // Monobank приймає суму в копійках!
        ccy: 980, // Код валюти UAH (Гривня)
        merchantPaymInfo: {
          reference: order_id.toString(),
          destination: `Оплата замовлення №${order_id}`,
        },
        paymentType: "hold", // 🔥 НАЙГОЛОВНІШЕ: Заморожуємо гроші, а не списуємо!
        // redirectUrl: "yourapp://payment/success", // Сюди повернемо клієнта після оплати (налаштуємо пізніше)
       webHookUrl: "https://ixdjtrixddggmermdbgv.supabase.co/functions/v1/mono-webhook",
      })
    })

    const data = await response.json()

    // Повертаємо посилання на сторінку оплати у Flutter
    return new Response(JSON.stringify(data), { 
      headers: { ...corsHeaders, 'Content-Type': 'application/json' } 
    })

  } catch (error) {
    return new Response(JSON.stringify({ error: error.message }), { 
      status: 400, 
      headers: { ...corsHeaders, 'Content-Type': 'application/json' } 
    })
  }
=======
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  // Обробка CORS для Flutter
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const { order_id, amount } = await req.json()
    
    // Беремо секретний токен Monobank із захищених змінних середовища Supabase
    const monoToken = Deno.env.get('MONOBANK_TOKEN')

    if (!monoToken) {
      throw new Error('Токен Monobank не налаштовано на сервері')
    }

    // Звертаємося до API Monobank
    const response = await fetch('https://api.monobank.ua/api/merchant/invoice/create', {
      method: 'POST',
      headers: {
        'X-Token': monoToken,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({
        amount: Math.round(amount * 100), // Monobank приймає суму в копійках!
        ccy: 980, // Код валюти UAH (Гривня)
        merchantPaymInfo: {
          reference: order_id.toString(),
          destination: `Оплата замовлення №${order_id}`,
        },
        paymentType: "hold", // 🔥 НАЙГОЛОВНІШЕ: Заморожуємо гроші, а не списуємо!
        // redirectUrl: "yourapp://payment/success", // Сюди повернемо клієнта після оплати (налаштуємо пізніше)
       webHookUrl: "https://ixdjtrixddggmermdbgv.supabase.co/functions/v1/mono-webhook",
      })
    })

    const data = await response.json()

    // Повертаємо посилання на сторінку оплати у Flutter
    return new Response(JSON.stringify(data), { 
      headers: { ...corsHeaders, 'Content-Type': 'application/json' } 
    })

  } catch (error) {
    return new Response(JSON.stringify({ error: error.message }), { 
      status: 400, 
      headers: { ...corsHeaders, 'Content-Type': 'application/json' } 
    })
  }
>>>>>>> 467667475cbaf79afed5ea350d290cd705acbd73
})