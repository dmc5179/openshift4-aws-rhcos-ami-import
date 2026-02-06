#!/bin/bash -xe
  
#############################################
#
# Update these 4 parameters for your use case
#
RHCOS_VERSION="4.20.13"     # RHCOS version, not OCP Version
RHCOS_TMP="/tmp"            # Location of the RHCOS VMDK GZ or where to download it to
S3_BUCKET="danclark-bucket" # S3 bucket to upload VMDK to
STORAGE_CLASS="gp3"         # Storage class for the AMI by default
#############################################

# Change to the temporary directory
pushd "${RHCOS_TMP}"

# NOTE: Uncomment the curl command if you need to download the disk
#       This script is assuming that has been done and we are now in the disconnected world
# Download the RHCOS metal image tarball
curl -O https://mirror.openshift.com/pub/openshift-v4/x86_64/dependencies/rhcos/${RHCOS_VERSION:0:4}/latest/rhcos-${RHCOS_VERSION}-x86_64-aws.x86_64.vmdk.gz

# Unpack the RHCOS metal image tarball
gunzip rhcos-${RHCOS_VERSION}-x86_64-aws.x86_64.vmdk.gz

cat << EOF > ./containers.json
{
    "Description": "rhcos-${RHCOS_VERSION}-x86_64-aws.x86_64",
    "Format": "VMDK",
    "UserBucket": {
        "S3Bucket": "${S3_BUCKET}",
        "S3Key": "rhcos-${RHCOS_VERSION}-x86_64-aws.x86_64.vmdk"
    }
}
EOF

# Copy the raw disk to S3
# It is best to just copy the image to the bucket root
# The default roles for snapshot import tend not to work well with sub paths
aws s3 cp "${RHCOS_TMP}/rhcos-${RHCOS_VERSION}-x86_64-aws.x86_64.vmdk" "s3://${S3_BUCKET}/rhcos-${RHCOS_VERSION}-x86_64-aws.x86_64.vmdk"

# Import the image as a snapshot
IMPORT_ID=$(aws ec2 import-snapshot \
    --description "rhcos-${RHCOS_VERSION}-x86_64-aws.x86_64" \
    --disk-container "file:///tmp/containers.json" \
    --output text --query 'ImportTaskId')

echo "Import ID: ${IMPORT_ID}"

echo "Use the following command to monitor the import process:"
echo "aws ec2 describe-import-snapshot-tasks --import-task-ids ${IMPORT_ID}"

echo "Waiting until the import completes"

STATUS="unknown"
until [[ ${STATUS} == deleted || ${STATUS} == completed ]]
do
  STATUS=$(aws ec2 describe-import-snapshot-tasks --import-task-ids ${IMPORT_ID} --output text --query 'ImportSnapshotTasks[*].SnapshotTaskDetail.Status')
  echo "Status: ${STATUS}"
  sleep 30
done

echo "Registering the image"
# Get the snapshot ID from the import task
SNAPSHOT_ID=$(aws ec2 describe-import-snapshot-tasks --import-task-ids \
                      ${IMPORT_ID} --output text --query 'ImportSnapshotTasks[*].SnapshotTaskDetail.SnapshotId')

# Register the image
aws ec2 register-image \
    --name "rhcos-${RHCOS_VERSION}-x86_64-aws.x86_64" \
    --ena-support \
    --block-device-mappings \
"[{\"DeviceName\": \"/dev/xvda\",\"Ebs\":{\"VolumeSize\":16,\"VolumeType\":\"${STORAGE_CLASS}\",\"DeleteOnTermination\":true,\"SnapshotId\":\"${SNAPSHOT_ID}\"}}]" \
    --root-device-name '/dev/xvda' \
    --architecture x86_64 \
    --root-device-name '/dev/xvda' \
    --description "rhcos-${RHCOS_VERSION}-x86_64-aws.x86_64" \
    --virtualization-type hvm
