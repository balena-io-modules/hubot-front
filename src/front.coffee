request = require 'request'
moment = require 'moment'
try
	{ Adapter, TextMessage } = require 'hubot'
catch
	prequire = require 'parent-require'
	{ Adapter, TextMessage } = prequire 'hubot'

class Front extends Adapter
	constructor: ->
		super
		@conversationsBeingProcessed = 0
		@conversationsBeingRequested = false
		@lastReport = null
		@lastCode = null

	send: (envelope, strings...) ->
		@robot.logger.info 'Send'

	reply: (envelope, strings...) ->
		@robot.logger.info 'Reply'

	run: ->
		setInterval @checkConversations, 1000 # API allows 120 requests per minute
		@emit 'connected'

	checkConversations: =>
		# Confirm that the previous request isn't still running
		if @conversationsBeingProcessed is 0 and @conversationsBeingRequested is false
			# Notice updated conversations (by referencing last_message)
			@conversationsBeingRequested = true
			@getUntil(
				@calcOptions '/conversations'
				(conversation) =>
					(conversation.last_message.id isnt @robot.brain.get('AdapterFrontLastKnown_' + conversation.id)) and
					(moment(conversation.last_message.created_at * 1000).isAfter(moment().subtract(7, 'd')))
				@processConversation
				(err) => @conversationsBeingRequested = false
			)

	getUntil: (options, filter, each, done) ->
		# Execute and callback a series of paged requests until we run out of pages or a filter rejects
		request.get? options, (error, response, body) =>
			@lastCode = response.statusCode
			if error or response.statusCode isnt 200
				@report()
				if response.statusCode in [429, 503]
					# Retry if the error code indicates temporary outage
					@getUntil options, filter, each, done
				else
					@robot.logger.error response.statusCode + '-' + options.url
					done { error, response }
			else
				responseObject = JSON.parse(body)
				for result in responseObject._results
					if filter result
						each result
					else
						done null
						@report()
						return
				if responseObject._pagination?.next?
					options.url = responseObject._pagination.next
					@getUntil options, filter, each, done
				else
					done null
					@report()

	report: =>
		report =
			'html': @lastCode
			'more': @conversationsBeingRequested
			'queue': @conversationsBeingProcessed
		report = JSON.stringify(report)
		if @lastReport isnt report
			@lastReport = report
			@robot.logger.debug report

	calcOptions: (endpoint) ->
		return {
			url: 'https://api2.frontapp.com' + endpoint
			headers:
				Accept: 'application/json'
				Authorization: 'Bearer ' + process.env.HUBOT_FRONT_API_TOKEN
		}

	processConversation: (conversation) =>
		# Get the new messages in a conversation
		@conversationsBeingProcessed++
		@getUntil(
			@calcOptions '/conversations/' + conversation.id + '/messages'
			(message) => message.id isnt @robot.brain.get('AdapterFrontLastKnown_' + conversation.id)
			@processMessage
			(err) =>
				if not err
					@robot.brain.set('AdapterFrontLastKnown_' + conversation.id, conversation.last_message.id)
				@conversationsBeingProcessed--
		)

	processMessage: (message) =>
		# Bundle the message into hubot format
		for identity in message.recipients
			if identity.role is 'from'
				author = @robot.brain.userForId(identity.handle, { name: identity.handle, room: 'blah' })
		message = new TextMessage(author, @robot.name + ': ' + message.text, message.id)
		@robot.receive(message)

exports.use = (robot) ->
	new Front robot
