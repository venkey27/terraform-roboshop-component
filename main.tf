# creating mongodb catalogue
resource "aws_instance" "main" {             
  ami           = local.ami_id  
  instance_type = "t3.micro"                     
  vpc_security_group_ids = [local.sg_id]  
  subnet_id = local.private_subnet_id
  

  tags = merge(
    {
        Name = "${local.common_name}" #roboshop-dev-catalogue
    },
    local.common_tags
  )
}


resource "terraform_data" "main" {          # here we are using terraform data for provisioner only 
  triggers_replace = [                           # trigger means when to run.  also can control terraform data by triggers
    aws_instance.main.id                    #  triggers_replace = aws_instance.redis.id : if any chnage in redis instance then triggers work, 
  ]                                                                         #no changes in redis instance then triggers dont work

  connection {
    type        = "ssh"
    user        = "ec2-user"
    password = "DevOps321"
    host        = aws_instance.main.private_ip  # only private because mongodb will not have public ip address because it is in private subnet
  }

  provisioner "file" {                               # purpose is to copy local file into remote resource 
    source      = "bootstrap.sh"
    destination = "/tmp/bootstrap.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/bootstrap.sh",
      "sudo sh /tmp/bootstrap.sh ${var.component} ${var.environment} ${var.app_version}"   # when we pass redis and environment here, 
    ]               # they go in bootstrap 15 line(ansible excution)     # - ansible-playbook -e component=$component -e env=$environment roboshop.yaml
  }
}

# Control the running state explicitly
resource "aws_ec2_instance_state" "main" {
  instance_id = aws_instance.main.id
  state       = "stopped"                          # Allowed values: "running" or "stopped" , state =  we can stop or run the instance state 
  depends_on = [ terraform_data.main ]            # means when terraform_data" "catalogue" configuration is done, 
                                               #  then after "aws_ec2_instance_state" "catalogue" configuration will run and stop the instaance 
}

# resource allows the creation of an Amazon Machine Image (AMI)              # AMI brings The Operating System (e.g., Linux, Windows
resource "aws_ami_from_instance" "main" {                               # Your code, installed software, and system files
  name               = "${local.common_name}-${var.component}-${var.app_version}-${aws_instance.main.id}"  # roboshop-dev-catalogue-v3-instance-id
  source_instance_id = aws_instance.main.id
  depends_on = [ aws_ec2_instance_state.main ]                # means when "aws_ec2_instance_state" "catalogue" INSTANCE STOPS completely , 
                                                         # then after "aws_ami_from_instance" "catalogue" configuration will run and creates AMI

  tags = merge(
    {
        Name = "${local.common_name}-${var.app_version}-${aws_instance.main.id}"
    },
    local.common_tags
  )
}

# resource allows the creation of an lunch template
resource "aws_launch_template" "main" {
  name = "${local.common_name}"    # form catalogue ami id

  image_id = aws_ami_from_instance.main.id

  instance_initiated_shutdown_behavior = "terminate"  # we get 2 options stop or terminate, we dont use stop because we have to pay extra money

  instance_type = "t3.micro"

  vpc_security_group_ids = [local.sg_id]

  update_default_version = true  # if lunch template is updated then take eww template by defult  

   # Once the instances are created, these will become instance tags
  tag_specifications {
    resource_type = "instance"

    tags = merge(
      {
          Name = "${local.common_name}-${var.app_version}-${aws_instance.main.id}"
      },
      local.common_tags
    )
  }

  # Once the instances are created, these will become volume tags
  tag_specifications {
    resource_type = "volume"

    tags = merge(
      {
          Name = "${local.common_name}-${var.app_version}-${aws_instance.main.id}"
      },
      local.common_tags
    )
  }  
}

# # resource allows the creation of an Target group
# resource "aws_lb_target_group" "main" {  # target consist of instances 
#   name     = "${local.common_name}"
#   port     = 8080
#   protocol = "HTTP"
#   vpc_id   = local.vpc_id
#   deregistration_delay = 30       # If there are users already connected to that server, the Load Balancer gives them exactly 30 seconds 
#                                   # to finish what they are doing (completing their download, saving their data, etc.).

#   health_check {               # {} means here block # target group consist of health check 
#     healthy_threshold = 2
#     interval = 10               # every 10 seconds health check will done
#     matcher = "200-299"
#     path = "/health"           
#     port = 8080
#     protocol = "HTTP"
#     timeout = 5                 # response should come in 5 seconds
#     unhealthy_threshold = 2     #  2 consecutive  health check fails then instance is not in good condition
#   }
# }

# # # resource allows the creation of an autoscaling
# # resource "aws_autoscaling_group" "catalogue" {
# #   name                      = "${local.common_name}-catalogue"
# #   max_size                  = 10                      # maxmimum number can autosacling can create 10 instances
# #   min_size                  = 1                       # always should maintian  2 instances 
# #   health_check_grace_period = 120                     # 120 = 2 min, do the health check after 2 minutes of instances got created 
# #   health_check_type         = "ELB"                   # load balancer will do health check
# #   desired_capacity          = 2                       # for now create 2 instances 
# #   force_delete              = false                   # after delation of instances then auto-sacling will have to delete 

# #   launch_template {
# #     id      = aws_launch_template.catalogue.id
# #     version = "$Latest"
# #   }

# #   vpc_zone_identifier       = [local.private_subnet_id]

# #   target_group_arns = [aws_lb_target_group.catalogue.arn] # Autoscaling launches into specific target group

# #   instance_refresh {   # if there is any changes in lunch template then referesh the instances 
# #     strategy = "Rolling"  # rolling means deleting old instance  and creating new instance
# #     preferences {
# #       min_healthy_percentage = 50
# #     }
# #     triggers = ["launch_template"]
# #   }

# #   dynamic "tag" {
# #     for_each = merge(
# #       {
# #         Name = "${local.common_name}-catalogue"
# #       },
# #       local.common_tags
# #     )
# #     content{
# #       key                 = tag.key
# #       value               = tag.value
# #       propagate_at_launch = true
# #     }
# #   }

# #   # with in 15min autoscaling should be successful to launch instances
# #   timeouts {
# #     delete = "15m"
# #   }
# # }

# # # auto-scaling policy creation for average cpu utilization 
# # resource "aws_autoscaling_policy" "catalogue" {
# #   autoscaling_group_name = aws_autoscaling_group.catalogue.name
# #   name                   = "${local.common_name}-catalogue"
# #   policy_type            = "TargetTrackingScaling"
# #   estimated_instance_warmup = 120
# #   target_tracking_configuration {
# #     predefined_metric_specification {
# #       predefined_metric_type = "ASGAverageCPUUtilization"
# #     }

# #     target_value = 75.0
# #   }
# # }

# # #create Listener rules for your Application Load Balancer (ALB).
# # resource "aws_lb_listener_rule" "catalogue" { # you are telling the Application Load Balancer how to route traffic to your different 
# #   listener_arn = local.backend_alb_listener_arn                                         #microservices (like your catalogue service).
# #   priority     = 10

# #   action {
# #     type             = "forward"
# #     target_group_arn = aws_lb_target_group.catalogue.arn   # Purpose: THEN do this. Because the condition matched, the Load Balancer says: 
# #   }                                                        #"Okay, take this traffic and forward it straight to the catalogue target group."

# #   condition {
# #     host_header {
# #       values = ["catalogue.backend-alb-${var.environment}.${var.domain_name}"]
# #     }  # Purpose: This checks the incoming traffic. IF a user types catalogue.backend-alb-dev-exptrack.shop into their browser, 
# #   }    # this condition evaluates to True.
# # }

# # resource "terraform_data" "catalogue_delete" { # to delete the 1st stopped catalogue instance to create AMI
# #   triggers_replace = [
# #     aws_instance.catalogue.id
# #   ]
# #   depends_on = [aws_autoscaling_policy.catalogue]

# #   # executes where terraform is running
# #   provisioner "local-exec" {
# #     command = "aws ec2 terminate-instances --instance-ids ${aws_instance.catalogue.id}"
# #   }
# # }  # Terraform provisioners (like local-exec), the command argument always requires a string, not a list.