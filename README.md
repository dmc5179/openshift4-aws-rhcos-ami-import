# openshift4-aws-rhcos-ami-import
openshift4-aws-rhcos-ami-import

# Create IAM role

```console
./create-role.sh <s3 bucket name to allow role operation on>
```

# Create the AMI

Update the following fields in the file rhcos_ami.sh
```
RHCOS_VERSION="4.20.13"     # RHCOS version, not OCP Version
RHCOS_TMP="/tmp"            # Location of the RHCOS VMDK GZ or where to download it to
S3_BUCKET="danclark-bucket" # S3 bucket to upload VMDK to
STORAGE_CLASS="gp3"         # Storage class for the AMI by default
```

Run the command
```console
./rhcos_ami.sh
```
