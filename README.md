# packer_centos8_demo #

This is an example of how to create your own CentOS 8 AMI via a bootstrap with kickstart from and existing AMI, since no official CentOS Marketplace release existed, and at the time I started this, no official AMIs at all and 3rd party releases that charged a premium.

It also demonstrates being able to customize the root volume, in this case using an LVM logical volume for the root filesystem instead of a fixed partition that can autoextend to the size of the instance volume at creation time.

Some ideas came from:

https://github.com/devopsmakers/centos7-hardened

Note that comments aren't permitted in a JSON file, so things to note in the centos8.json file:

- min_packer_version: This will probably work on earlier version, but this is the version I happened to be using.
- I've defined a number of variables to use later in the file at the top, so you don't need go through all of the file to make changes
- aws_access_key, aws_secret_key and aws_session_token should be left blank
- Substitute the aws_region, vpc_id and subnet_id where you want to run the temporary instance to create your AMI
- aws_instance_type: A bigger instance doesn't really make this go faster.
- I'm using an AMI filter to choose the latest official CentOS 7 Marketplace AMI, hence the product code and owner.
- I create a "default_user" of centos, to match official images
- The default root volume size is 8GB, which seems the smallest reasonable size, but the AMI will automatically expand the root filesystem/logical volume to any instance volume greater than that.


