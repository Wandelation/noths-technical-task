# Create SQS queue to subscribe to SNS topic basket-events
resource "aws_sqs_queue" "basket_queue" {
  name = "orange-ritual-basket_queue"
}

# Apply the basket_queue_policy to the basket_qeueue
resource "aws_sqs_queue_policy" "basket_queue_policy" {
  queue_url = aws_sqs_queue.basket_queue.id
  policy    = data.aws_iam_policy_document.basket_policy.json
}

# Subscribe basket_queue to the exisisting basket SNS topic
resource "aws_sns_topic_subscription" "basket_topic_subscription" {
  topic_arn            = var.basket_sns_topic_arn 
  protocol             = "sqs"
  raw_message_delivery = true
  endpoint             = aws_sqs_queue.basket_queue.arn 
}

# Create SQS queue to subscribe to SNS topic checkout-events
resource "aws_sqs_queue" "checkout_queue" {
  name = "orange-ritual-checkout_queue"
}

# Apply the checkout_queue_policy to the checkout_queue
resource "aws_sqs_queue_policy" "checkout_queue_policy" {
  queue_url = aws_sqs_queue.checkout_queue.id
  policy    = data.aws_iam_policy_document.checkout_policy.json
}

# Subscribe the checkout_queue to the existing checkout SNS topic
resource "aws_sns_topic_subscription" "checkout_topic_subscription" {
  topic_arn            = var.checkout_sns_topic_arn 
  protocol             = "sqs"
  raw_message_delivery = true
  endpoint             = aws_sqs_queue.checkout_queue.arn 
}

# Define EventBridge pipes
resource "aws_pipes_pipe" "events_basket_pipe" {
  name     = "orange-ritual-basket-pipe"
  source   = aws_sqs_queue.basket_queue.arn
  target   = var.domain_events_bus_arn
  role_arn = aws_iam_role.eventbridge_role.arn
  target_parameters {
	  input_template = <<-EOT
		{ "event": <$.body> }
	  EOT
	}
}

resource "aws_pipes_pipe" "events_checkout_pipe" {
  name     = "orange-ritual-checkout-pipe"
  source   = aws_sqs_queue.checkout_queue.arn
  target   = var.domain_events_bus_arn
  role_arn = aws_iam_role.eventbridge_role.arn
  target_parameters {
	  input_template = <<-EOT
		{ "event": <$.body> }
	  EOT
	}
}

# Create the end-target SQS queue
resource "aws_sqs_queue" "sqs_purchase_queue" {
  name = "orange-ritual-purchase-events"
}

# Create a debugging log group
# I used this to initially send all messages to this group
# So that I could verify the pipes working and look at the
# messages to help refine the pattern matching later. 
resource "aws_cloudwatch_log_group" "cloudwatch_log_group" {
  name              = "/orange-ritual/aws/events/pipe-events"
  retention_in_days = 5
}

# Define cloudwatch event rule to redirect
# messages from the checkout pipe
resource "aws_cloudwatch_event_rule" "checkout_rule" {
  name           = "orange-ritual-checkout_rule"
  event_bus_name = var.domain_events_bus_arn
  event_pattern  = jsonencode(
	{
	  "source" : [
		"Pipe orange-ritual-checkout-pipe"
	  ]
	}
  )
}

# Set the target for the checkout rule to be the SQS purchase queue
# I've left the bit of code I used while debugging in a cloudwatch log group
# commented out as a reference
resource "aws_cloudwatch_event_target" "checkout_target" {
  rule           = aws_cloudwatch_event_rule.checkout_rule.name
  # arn          = aws_cloudwatch_log_group.cloudwatch_log_group.arn
  arn            = aws_sqs_queue.sqs_purchase_queue.arn
  event_bus_name = var.domain_events_bus_arn
}

# Define cloudwatch event rule to redirect
# messages from the basket pipe
resource "aws_cloudwatch_event_rule" "basket_rule" {
  name           = "orange-ritual-basket_rule"
  event_bus_name = var.domain_events_bus_arn
  event_pattern  = jsonencode(
	{
	  "source" : [
		"Pipe orange-ritual-basket-pipe"
	  ]
	}
  )
}

# Set the target for the basket rule to be the SQS purchase queue
# I've left the bit of code I used while debugging in a cloudwatch log group
# commented out as a reference
resource "aws_cloudwatch_event_target" "basket_target" {
  rule           = aws_cloudwatch_event_rule.basket_rule.name
  # arn          = aws_cloudwatch_log_group.cloudwatch_log_group.arn
  arn            = aws_sqs_queue.sqs_purchase_queue.arn
  event_bus_name = var.domain_events_bus_arn
}

# Apply the SQS purchase_queue policy to the purchase_queue
resource "aws_sqs_queue_policy" "purchase_queue_policy" {
  queue_url = aws_sqs_queue.sqs_purchase_queue.id
  policy    = data.aws_iam_policy_document.purchase_policy.json
}