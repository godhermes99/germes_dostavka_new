import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.7.1'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const { order_id, action, amount } = await req.json()

    // ЖУЧОК 1: Дивимося, що саме прислала адмінка (Flutter)
    console.log(`[START] Дія: ${action}, Отриманий order_id:`, order_id)

    const monoToken = Deno.env.get('MONOBANK_TOKEN')
    if (!monoToken) throw new Error('Токен Monobank не налаштовано')

    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    )

    const { data: order, error: orderError } = await supabaseAdmin
      .from('orders')
      .select('id, payment_id, total_amount')
      .eq('id', order_id)
      .single()

    // ЖУЧОК 2: Дивимося, що знайшлося в базі
    console.log(`[DB RESULT] Замовлення:`, order, `Помилка БД:`, orderError)

    if (orderError) {
      throw new Error(`Замовлення з ID [${order_id}] не знайдено в базі даних!`)
    }

    if (!order?.payment_id) {
      throw new Error(`Замовлення знайдено, але колонка payment_id ПОРОЖНЯ!`)
    }

    const invoiceId = order.payment_id

    let url = ''
    let bodyData: any = { invoiceId }

    if (action === 'capture') {
      url = 'https://api.monobank.ua/api/merchant/invoice/finalize'
      const finalAmount = amount ? amount : order.total_amount
      bodyData.amount = Math.round(finalAmount * 100)
    } else if (action === 'cancel') {
      url = 'https://api.monobank.ua/api/merchant/invoice/cancel'
      // Виправив урл, прибрав зайве ".api"
    } else {
      throw new Error('Невідома дія')
    }

    // ЖУЧОК 3: Дивимося запит до Монобанку
    console.log(`[MONO REQUEST] URL: ${url}, Body:`, bodyData)

    const response = await fetch(url, {
      method: 'POST',
      headers: {
        'X-Token': monoToken,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify(bodyData)
    })

    const monoData = await response.json()
    console.log(`[MONO RESPONSE]`, monoData)

    if (!response.ok) {
      throw new Error(monoData.errText || 'Помилка банку при транзакції')
    }

    const newStatus = action === 'capture' ? 'Готується' : 'Скасовано'

    const { error: updateError } = await supabaseAdmin
      .from('orders')
      .update({ status: newStatus })
      .eq('id', order_id)

    if (updateError) throw updateError

    return new Response(JSON.stringify({ success: true, newStatus }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    })

  } catch (error) {
    console.error('[FATAL ERROR]:', error.message)
    return new Response(JSON.stringify({ error: error.message }), { 
      status: 400, 
      headers: { ...corsHeaders, 'Content-Type': 'application/json' } 
    })
  }
})