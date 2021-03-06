
config = require '../../../server_config'
require '../common'

# sample data that comes in through the webhook when you subscribe


describe '/db/user, editing stripe.couponID property', ->

  stripe = require('stripe')(config.stripe.secretKey)
  userURL = getURL('/db/user')
  webhookURL = getURL('/stripe/webhook')

  it 'clears the db first', (done) ->
    clearModels [User, Payment], (err) ->
      throw err if err
      done()

  #- shared data between tests
  joeData = null
  firstSubscriptionID = null
  
  it 'does not work for non-admins', (done) ->
    loginJoe (joe) ->
      joeData = joe.toObject()
      expect(joeData.stripe).toBeUndefined()
      joeData.stripe = { couponID: '20pct' }
      request.put {uri: userURL, json: joeData }, (err, res, body) ->
        expect(res.statusCode).toBe(200) # fails silently
        expect(res.body.stripe).toBeUndefined() # but still fails
        done()
        
  it 'does not work with invalid coupons', (done) ->
    loginAdmin (admin) ->
      joeData.stripe = { couponID: 'DNE' }
      request.put {uri: userURL, json: joeData }, (err, res, body) ->
        expect(res.statusCode).toBe(404)
        done()
  
  it 'sets the couponID on a user without an existing stripe object', (done) ->
    joeData.stripe = { couponID: '20pct' }
    request.put {uri: userURL, json: joeData }, (err, res, body) ->
      joeData = body
      expect(res.statusCode).toBe(200)
      expect(body.stripe.couponID).toBe('20pct')
      done()
      
  it 'just updates the couponID when it changes and there is no existing subscription', (done) ->
    joeData.stripe.couponID = '500off'
    request.put {uri: userURL, json: joeData }, (err, res, body) ->
      expect(res.statusCode).toBe(200)
      expect(body.stripe.couponID).toBe('500off')
      done()

  it 'removes the couponID from the user when the admin makes it so', (done) ->
    delete joeData.stripe.couponID
    request.put {uri: userURL, json: joeData }, (err, res, body) ->
      joeData = body
      expect(res.statusCode).toBe(200)
      expect(body.stripe).toBeUndefined()
      done()

  it 'puts the coupon back', (done) ->
    joeData.stripe = {couponID: '500off'}
    request.put {uri: userURL, json: joeData }, (err, res, body) ->
      expect(res.statusCode).toBe(200)
      expect(body.stripe.couponID).toBe('500off')
      done()

  it 'applies a discount to the newly created customer when a plan is set', (done) ->
    stripe.tokens.create {
      card: { number: '4242424242424242', exp_month: 12, exp_year: 2020, cvc: '123' }
    }, (err, token) ->
      stripeTokenID = token.id
      loginJoe (joe) ->
        joeData.stripe.token = stripeTokenID
        joeData.stripe.planID = 'basic'
        request.put {uri: userURL, json: joeData, headers: {'X-Change-Plan': 'true'} }, (err, res, body) ->
          joeData = body
          expect(res.statusCode).toBe(200)
          stripe.customers.retrieve joeData.stripe.customerID, (err, customer) ->
            expect(customer.discount).toBeDefined()
            expect(customer.discount.coupon.id).toBe('500off')
            done()
  
          
  it 'updates the discount on the customer when an admin changes the couponID', (done) ->
    loginAdmin (admin) ->
      joeData.stripe.couponID = '20pct'
      request.put {uri: userURL, json: joeData }, (err, res, body) ->
        expect(res.statusCode).toBe(200)
        expect(body.stripe.couponID).toBe('20pct')
        stripe.customers.retrieve joeData.stripe.customerID, (err, customer) ->
          expect(customer.discount.coupon.id).toBe('20pct')
          done()
      
  it 'removes discounts from the customer when an admin removes the couponID', (done) ->
    delete joeData.stripe.couponID
    request.put {uri: userURL, json: joeData }, (err, res, body) ->
      expect(res.statusCode).toBe(200)
      expect(body.stripe.couponID).toBeUndefined()
      stripe.customers.retrieve joeData.stripe.customerID, (err, customer) ->
        expect(customer.discount).toBe(null)
        done()

  it 'adds a discount to the customer when an admin adds the couponID', (done) ->
    joeData.stripe.couponID = '20pct'
    request.put {uri: userURL, json: joeData }, (err, res, body) ->
      expect(res.statusCode).toBe(200)
      expect(body.stripe.couponID).toBe('20pct')
      stripe.customers.retrieve joeData.stripe.customerID, (err, customer) ->
        expect(customer.discount.coupon.id).toBe('20pct')
        done()
        
