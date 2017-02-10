moment = require 'moment'
AbstractAPIAdapter = require 'hubot-abstract-api-adapter'
try
	{ TextMessage } = require 'hubot'
catch
	prequire = require 'parent-require'
	{ TextMessage } = prequire 'hubot'

###*
	GOTCHA ALERT! Because of the, IMO, slightly confusing way that front handles inboxes/channels
	GOTCHA ALERT! There has had to be a slightly confusing amalgamation of terms.
	GOTCHA ALERT! A message is posted to a channel, which front then aggregates, and an event is emitted from an inbox.
	TODO: https://github.com/resin-io-modules/hubot-front/issues/12
###
class Front extends AbstractAPIAdapter
	constructor: ->
		try
			super
		catch error
			if error not instanceof TypeError
				throw error

	extractNext: (obj) -> obj._pagination?.next

	extractResults: (obj) -> obj._results

	poll: =>
		checkHistoryUntil = @robot.brain.get 'AdapterFrontLastKnown'
		if not checkHistoryUntil?
			firstCheckWindow = parseInt(process.env.HUBOT_FRONT_SYNC_HISTORY ? '24')
			checkHistoryUntil = moment().subtract(firstCheckWindow, 'h').unix()
		@getUntil(
			@getOptions process.env.HUBOT_FRONT_API_URL + '/events'
			@processMessage
			(obj) -> obj.emitted_at > checkHistoryUntil
			(err, res) => if not err then @robot.brain.set('AdapterFrontLastKnown', res[0].emitted_at)
		)

	getOptions: (url) ->
		url: url
		headers:
			Accept: 'application/json'
			Authorization: 'Bearer ' + process.env.HUBOT_FRONT_API_TOKEN
		qs:
			before: Date.now()

	processMessage: (message) =>
		if message.type in [
			'inbound', 'comment', 'email', 'intercom', 'out-reply'
			'reopen', 'outbound', 'move', 'sending-error', 'reminder'
		]
			@getUntil(
				@getOptions message.conversation._links.related.inboxes
				@tellHubot message
			)

	tellHubot: (message) -> (inbox) =>
		if message.target?.data?.author?
			author = @robot.brain.userForId(
				message.target.data.author.id
				{ name: message.target.data.author.username, room: inbox.id }
			)
		else
			for recipient in message?.target?.data?.recipients ? []
				if recipient.role is 'from'
					author = @robot.brain.userForId(
						recipient.handle
						{ name: recipient.handle, room: inbox.id }
					)
		@robot.receive new TextMessage(
			author
			@robot.name + ': ' + message.target?.data?.text
			message.id
			{ ids: { comment: message.id, thread: message.conversation?.id, flow: inbox.id } }
		)

	parseResponse: (response) -> thread: response.conversation_reference.split('@')[0]

	buildRequest: (user, channel, text, conversation) ->
		returnValue =
			payload:
				body: text
			headers:
				'Content-Type': 'application/json'
				Accept: 'application/json'
				Authorization: "Bearer #{user}"
		if conversation?
			# http://dev.frontapp.com/#send-reply
			returnValue.url = "https://api2.frontapp.com/conversations/#{conversation}/messages"
		else
			# http://dev.frontapp.com/#send-new-message
			returnValue.url = "https://api2.frontapp.com/channels/#{channel}/messages"
		returnValue

exports.use = (robot) ->
	new Front robot
