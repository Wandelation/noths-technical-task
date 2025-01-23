# Define the policy for sending messages to basket_queue
data "aws_iam_policy_document" "basket_policy" {
  statement {
	sid    = "First"
	effect = "Allow"
	
	principals {
	  type = "*"
	  identifiers = ["*"]
	}
  
	actions   = ["sqs:SendMessage"]
	resources = [aws_sqs_queue.basket_queue.arn]
  
	condition {
	  test     = "ArnEquals"
	  variable = "aws:SourceArn"
	  values   = [var.basket_sns_topic_arn]
	}
  }
} 

# Define the policy for sending messages to checkout_queue
data "aws_iam_policy_document" "checkout_policy" {
  statement {
	sid    = "First"
	effect = "Allow"
	
	principals {
	  type        = "*"
	  identifiers = ["*"]
	}
  
	actions   = ["sqs:SendMessage"]
	resources = [aws_sqs_queue.checkout_queue.arn]
  
	condition {
	  test     = "ArnEquals"
	  variable = "aws:SourceArn"
	  values   = [var.checkout_sns_topic_arn]
	}
  }
} 

# Define IAM role for EventBridge
data "aws_caller_identity" "main" {}

resource "aws_iam_role" "eventbridge_role" {
  name = "orange-ritual-eventbridge-role"
  assume_role_policy = jsonencode({
	Version = "2012-10-17"
	Statement = {
	  Effect    = "Allow"
	  Action    = "sts:AssumeRole"
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

# Define policy for reading basket and checkout SQS queues
# and writing to Event Bus
resource "aws_iam_role_policy" "eventbridge_role_policy" {
  name = "orange-ritual-eventbridge-policy"
  role = aws_iam_role.eventbridge_role.id

  policy = jsonencode({
	Version   = "2012-10-17"
	Statement = [
	  {
		Effect = "Allow"
		Action = [
		  "sqs:DeleteMessage",
		  "sqs:GetQueueAttributes",
		  "sqs:ReceiveMessage",
		],
		Resource = [
		  aws_sqs_queue.basket_queue.arn, aws_sqs_queue.checkout_queue.arn
		]
	  },
	  {
		Effect = "Allow"
		Action = [
		  "events:PutEvents"
		]
		Resource = var.domain_events_bus_arn
	  }
	]
  })
}

# Define the policy for writing to cloudwatch log group
data "aws_iam_policy_document" "cloudwatch_log_policy" {
  statement {
	effect  = "Allow"
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
	effect  = "Allow"
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

# Define the policy for the eventbridge rules to write to SQS
data "aws_iam_policy_document" "purchase_policy" {
  statement {
	sid    = "First"
	effect = "Allow"
	
	principals {
	  type        = "*"
	  identifiers = ["*"]
	}
  
	actions   = ["sqs:SendMessage"]
	resources = [aws_sqs_queue.sqs_purchase_queue.arn]
  
	condition {
	  test     = "ArnEquals"
	  variable = "aws:SourceArn"
	  values   = [aws_cloudwatch_event_rule.basket_rule.arn, aws_cloudwatch_event_rule.checkout_rule.arn]
	}
  }
} 