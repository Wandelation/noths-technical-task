# Variables for existing ARNs
variable "basket_sns_topic_arn" {
  description = "The ARN of the existing basket SNS topic"
  type = string
  default = "arn:aws:sns:eu-west-1:536697261635:orange-ritual-basket-events"
}

variable "checkout_sns_topic_arn" {
  description = "The ARN of the existing checkout SNS topic"
  type = string
  default = "arn:aws:sns:eu-west-1:536697261635:orange-ritual-checkout-events"
}

variable "domain_events_bus" {
  description = "The ARN of the existing domain events event bus"
  type = string
  default = "arn:aws:events:eu-west-1:536697261635:event-bus/orange-ritual-domain-events"
}