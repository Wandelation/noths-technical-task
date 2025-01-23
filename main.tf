terraform {
  required_providers {
	aws = {
	  source  = "hashicorp/aws"
	  version = "~> 5.0"
	}
  }
}

provider "aws" {
  region = "eu-west-1"
  shared_config_files = ["~/.aws/config"]
  shared_credentials_files = ["~/.aws/credentials"]
  profile = "noths"
}

# Set up an SQS queue to subscribe to SNS topic basket-events
resource "aws_sqs_queue" "basket_queue" {
  name = "orange-ritual-basket_queue"
}

data "aws_iam_policy_document" "basket_policy" {
  statement {
    sid = "First"
	effect = "Allow"
	
    principals {
      type = "*"
	  identifiers = ["*"]
    }
  
    actions = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.basket_queue.arn]
  
    condition {
	  test = "ArnEquals"
	  variable = "aws:SourceArn"
	  values = [var.basket_sns_topic_arn]
    }
  }
} 

resource "aws_sqs_queue_policy" "basket_queue_policy" {
  queue_url = aws_sqs_queue.basket_queue.id
  policy = data.aws_iam_policy_document.basket_policy.json
}

resource "aws_sns_topic_subscription" "basket_topic_subscription" {
  topic_arn = var.basket_sns_topic_arn 
  protocol = "sqs"
  raw_message_delivery = true
  endpoint = aws_sqs_queue.basket_queue.arn 
}

# Set up an SQS queue to subscribe to SNS topic checkout-events
resource "aws_sqs_queue" "checkout_queue" {
  name = "orange-ritual-checkout_queue"
}

data "aws_iam_policy_document" "checkout_policy" {
  statement {
	sid = "First"
	effect = "Allow"
	
	principals {
	  type = "*"
	  identifiers = ["*"]
	}
  
	actions = ["sqs:SendMessage"]
	resources = [aws_sqs_queue.checkout_queue.arn]
  
	condition {
	  test = "ArnEquals"
	  variable = "aws:SourceArn"
	  values = [var.checkout_sns_topic_arn]
	}
  }
} 

resource "aws_sqs_queue_policy" "checkout_queue_policy" {
  queue_url = aws_sqs_queue.checkout_queue.id
  policy = data.aws_iam_policy_document.checkout_policy.json
}

resource "aws_sns_topic_subscription" "checkout_topic_subscription" {
  topic_arn = var.checkout_sns_topic_arn 
  protocol = "sqs"
  raw_message_delivery = true
  endpoint = aws_sqs_queue.checkout_queue.arn 
}

# Define IAM role for EventBridge
data "aws_caller_identity" "main" {}

resource "aws_iam_role" "eventbridge_role" {
  name = "orange-ritual-eventbridge-role"
  assume_role_policy = jsonencode({
	Version = "2012-10-17"
	Statement = {
	  Effect = "Allow"
	  Action = "sts:AssumeRole"
	  Principal = {
		Service = "pipes.amazonaws.com"
	  }
	  Condition = {
		StringEquals = {
		  "aws:SourceAccount" = data.aws_caller_identity.main.account_id
		}
	  }
	}
  })
}

# Define policy for reading SQS and writing to Event Bus
resource "aws_iam_role_policy" "eventbridge_role_policy" {
  name = "orange-ritual-eventbridge-policy"
  role = aws_iam_role.eventbridge_role.id

  policy = jsonencode({
	Version = "2012-10-17"
	Statement = [
      {
		Effect = "Allow"
		Action = [
		  "sqs:DeleteMessage",
		  "sqs:GetQueueAttributes",
		  "sqs:ReceiveMessage",
		],
		Resource = [
		  aws_sqs_queue.basket_queue.arn,
		]
	  },
	  {
		  Effect = "Allow"
		  Action = [
			"sqs:DeleteMessage",
			"sqs:GetQueueAttributes",
			"sqs:ReceiveMessage",
		  ],
		  Resource = [
			aws_sqs_queue.checkout_queue.arn,
		  ]
		},
	  {
		Effect = "Allow"
		Action = [
		  "events:PutEvents"
		]
		Resource = var.domain_events_bus
	  }
	]
  })
}

# Define EventBridge pipes
resource "aws_pipes_pipe" "events_basket_pipe" {
  #depends_on = [aws_iam_role_policy.eventbridge_role_policy]
  name   = "orange-ritual-basket-pipe"
  source = aws_sqs_queue.basket_queue.arn
  target = var.domain_events_bus
  role_arn = aws_iam_role.eventbridge_role.arn
  target_parameters {
	  input_template = <<-EOT
		{ "event": <$.body> }
	  EOT
	}
}

resource "aws_pipes_pipe" "events_checkout_pipe" {
  depends_on = [aws_iam_role_policy.eventbridge_role_policy]
  name   = "orange-ritual-checkout-pipe"
  source = aws_sqs_queue.checkout_queue.arn
  target = var.domain_events_bus
  role_arn = aws_iam_role.eventbridge_role.arn
  target_parameters {
	  input_template = <<-EOT
		{ "event": <$.body> }
	  EOT
	}
}

# Define the target SQS queue
resource "aws_sqs_queue" "sqs_purchase_queue" {
  name  = "orange-ritual-purchase-events"
}

# Create a debugging log group
resource "aws_cloudwatch_log_group" "cloudwatch_log_group" {
  name = "/orange-ritual/aws/events/pipe-events"
  retention_in_days = 5
}

data "aws_iam_policy_document" "cloudwatch_log_policy" {
  statement {
	effect = "Allow"
	actions = [
	  "logs:CreateLogStream"
	]

	resources = [
	  "${aws_cloudwatch_log_group.cloudwatch_log_group.arn}:*"
	]

	principals {
	  type = "Service"
	  identifiers = [
		"events.amazonaws.com",
		"delivery.logs.amazonaws.com"
	  ]
	}
  }
  statement {
	effect = "Allow"
	actions = [
	  "logs:PutLogEvents"
	]

	resources = [
	  "${aws_cloudwatch_log_group.cloudwatch_log_group.arn}:*:*"
	]

	principals {
	  type = "Service"
	  identifiers = [
		"events.amazonaws.com",
		"delivery.logs.amazonaws.com"
	  ]
	}
  }
}

resource "aws_cloudwatch_event_rule" "checkout_rule" {
  name        = "orange-ritual-checkout_rule"
  event_bus_name = "arn:aws:events:eu-west-1:536697261635:event-bus/orange-ritual-domain-events"
  event_pattern = jsonencode(
	{
	  "source" : [
		"Pipe orange-ritual-checkout-pipe"
	  ]
	}
  )
}

resource "aws_cloudwatch_event_target" "checkout_target" {
  rule = aws_cloudwatch_event_rule.checkout_rule.name
  #arn  = aws_cloudwatch_log_group.cloudwatch_log_group.arn
  arn  = aws_sqs_queue.sqs_purchase_queue.arn
  event_bus_name = "arn:aws:events:eu-west-1:536697261635:event-bus/orange-ritual-domain-events"
}

resource "aws_cloudwatch_event_rule" "basket_rule" {
  name        = "orange-ritual-basket_rule"
  event_bus_name = "arn:aws:events:eu-west-1:536697261635:event-bus/orange-ritual-domain-events"
  event_pattern = jsonencode(
	{
	  "source" : [
		"Pipe orange-ritual-basket-pipe"
	  ]
	}
  )
}

resource "aws_cloudwatch_event_target" "basket_target" {
  rule = aws_cloudwatch_event_rule.basket_rule.name
  #arn  = aws_cloudwatch_log_group.cloudwatch_log_group.arn
  arn  = aws_sqs_queue.sqs_purchase_queue.arn
  event_bus_name = "arn:aws:events:eu-west-1:536697261635:event-bus/orange-ritual-domain-events"
}

# Allow eventbridge rule to write to SQS
data "aws_iam_policy_document" "purchase_policy" {
  statement {
	sid = "First"
	effect = "Allow"
	
	principals {
	  type = "*"
	  identifiers = ["*"]
	}
  
	actions = ["sqs:SendMessage"]
	resources = [aws_sqs_queue.sqs_purchase_queue.arn]
  
	condition {
	  test = "ArnEquals"
	  variable = "aws:SourceArn"
	  values = [aws_cloudwatch_event_rule.basket_rule.arn, aws_cloudwatch_event_rule.checkout_rule.arn]
	}
  }
} 

resource "aws_sqs_queue_policy" "purchase_queue_policy" {
  queue_url = aws_sqs_queue.sqs_purchase_queue.id
  policy = data.aws_iam_policy_document.purchase_policy.json
}