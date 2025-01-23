# Variables for existing ARNs
variable "basket_sns_topic_arn" {
  description = "The ARN of the existing basket SNS topic"
  type = string
}

variable "checkout_sns_topic_arn" {
  description = "The ARN of the existing checkout SNS topic"
  type = string
}

variable "domain_events_bus_arn" {
  description = "The ARN of the existing domain events event bus"
  type = string
}