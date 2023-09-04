# cicd-test

# 실습

## 운영서버이라 가정하고 CICD를 구성해보자

### 사용 스펙: Github actions, codeDeploy, S3, ECR, load balancer

**git repository: https://github.com/junchanpp/cicd-test**

---

## VPC 설정

그림과 같이 구상할 예정(각각의 역할에 대해서는 https://keencho.github.io/posts/aws-cicd-1/ 참고 후 자세한 설명은 인터넷 검색 추천, NAT gateway는 유료 서비스이므로, ap-norteast-2a에만 배치할 예정, 다른 가용영역에 있더라도, 라우팅테이블을 통해서 매핑되므로 문제없음)

NAT gateway같은 경우, NAT instance로 대체가 가능. 더 싸지만, 장애 발생 시, 책임의 소지가 본인에게 있음.

![image](https://github.com/junchanpp/cicd-test/assets/49396352/762a4322-cdd8-4a00-ba61-a7fc0195131f)


- https://keencho.github.io/posts/aws-cicd-1/를 참고하여 설정하여도 좋고, 아래와 같이 설정해도 좋다.

![image](https://github.com/junchanpp/cicd-test/assets/49396352/b9130398-b88b-4860-963b-cca68fb319ce)


- 생성할 리소스를 VPC등을 선택하여 한 번에 vpc 외의 subnet, routing table, internet gateway, NAT gateway가 생성되도록 했다.
- IPv4 CIDR 블록은 스터디 중 network 시간에 배운 대로 권장사항으로 입력하였음.

![image](https://github.com/junchanpp/cicd-test/assets/49396352/28fc495f-897a-44a2-a494-7e818d463bb4)



- 우리가 인스턴스로 이용할 t2-micro는 가용영역을 ap-northeast-2a와 ap-northeast-2c만 지원하므로(b,d는 지원 x) 인스턴스가 올라갈 수 있는 2a,2c로 지정했음
- 퍼블릭 서브넷과 프라이빗 서브넷의 역할은 블로그 참고(간단하게 설명하면, 보안적인 이유로 분리)

![image](https://github.com/junchanpp/cicd-test/assets/49396352/6b1fc43f-ed36-4658-812a-9ce8ee31c3c3)


- NAT 게이트웨이는 유료이므로 하나만 설정
- VPC 엔드포인트 관련 설명은 아래 참고. 간단히 설명하자면, aws 내부서비스는 NAT gateway를 사용하지 않음으로써 비용 절약
    - [https://inpa.tistory.com/entry/AWS-📚-VPC-End-Point-개념-원리-구축-세팅#게이트웨이_엔드포인트](https://inpa.tistory.com/entry/AWS-%F0%9F%93%9A-VPC-End-Point-%EA%B0%9C%EB%85%90-%EC%9B%90%EB%A6%AC-%EA%B5%AC%EC%B6%95-%EC%84%B8%ED%8C%85#%EA%B2%8C%EC%9D%B4%ED%8A%B8%EC%9B%A8%EC%9D%B4_%EC%97%94%EB%93%9C%ED%8F%AC%EC%9D%B8%ED%8A%B8)
    - [https://blog.bespinglobal.com/post/aws-vpc-s3-endpoint-gateway-vs-interface-차이/](https://blog.bespinglobal.com/post/aws-vpc-s3-endpoint-gateway-vs-interface-%EC%B0%A8%EC%9D%B4/)
- 결과

![image](https://github.com/junchanpp/cicd-test/assets/49396352/5db32c23-d8e0-461c-8eb7-01aaf10070f2)


- 위에 설명한대로 구성하면 routing 테이블이 조금 다를텐데, 기본 라우팅 테이블을 public으로 변경 후, 기존의 기본 라우팅 테이블을 삭제하고, private 라우팅 테이블은 하나로 합쳤음.

---

## IAM 설정

### Policy

- **S3 Access Policy(autoscaling 그룹을 통해 생성된 EC2에서 사용, deploy script를 가져오는 용도)**

```bash
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Action": [
                "s3:Get*",
                "s3:List*"
            ],
            "Effect": "Allow",
            "Resource": "*"
        }
    ]
}
```

- **ECR Access Policy(위와 같은 EC2에서 사용, 배포할 was의 image를 가져오는 용도)**
    - ECR Public은 서울은 지원안하므로, region은 버지니아 북부 추천(Private은 상관없는거같기도)
    - 나머지는 상황에 맞게 추천

```bash
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "GrantSingleImageReadOnlyAccess",
            "Effect": "Allow",
            "Action": [
                "ecr:BatchCheckLayerAvailability",
                "ecr:GetDownloadUrlForLayer",
                "ecr:GetRepositoryPolicy",
                "ecr:DescribeRepositories",
                "ecr:ListImages",
                "ecr:DescribeImages",
                "ecr:BatchGetImage"
            ],
            "Resource": "arn:aws:ecr:${region}:${aws_id}:repository/${img_name}"
        },
        {
            "Sid": "GrantECRAuthAccess",
            "Effect": "Allow",
            "Action": "ecr:GetAuthorizationToken",
            "Resource": "*"
        }
    ]
}
```

- **CodeDeploy Auto Scaling Policy(CodeDeploy에서 Auto Scaling에 접근할 수 있는 권한 정책)**

```bash
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "VisualEditor0",
            "Effect": "Allow",
            "Action": [
                "iam:PassRole",
                "ec2:CreateTags",
                "ec2:RunInstances"
            ],
            "Resource": "*"
        }
    ]
}
```

![image](https://github.com/junchanpp/cicd-test/assets/49396352/5d2f274b-8d15-4a9e-8570-ce11f72d047c)


### Role

- **Auto Scaling Role(위에서 만든 S3관련 Policy와 ECR관련 Policy를 연결)**
    
    ![image](https://github.com/junchanpp/cicd-test/assets/49396352/8daeb1cc-a779-4eb7-8b81-ef7cd7442993)

    
    ![image](https://github.com/junchanpp/cicd-test/assets/49396352/39055377-4ec0-4711-bb0a-84c2569430f6)

    
- **CodeDeploy Auto Scaling Role(CodeDeploy 앱에게 권한을 주는 role, 위에서 만든 CodeDeploy Auto Scaling policy와 AWS에서 기본적으로 제공하는** **AWSCodeDeployRole를 연결)**
    
    ![image](https://github.com/junchanpp/cicd-test/assets/49396352/fffb6326-c66a-4f36-b494-20a85728b0b9)

    
    - 위와 같이 codeDeploy를 선택해야 함
    
    ![image](https://github.com/junchanpp/cicd-test/assets/49396352/e130ceda-1f49-4e67-b5c1-b8ecbd24a72a)

    

---

## ECR 생성

- Elastic Container Registry 검색 후 public registry 생성 후 기본별칭을 기억해주세요.(마지막에 코드 작성할 때 쓰임)
- 그 후, 퍼블릭 리포지토리 생성

---

## S3 생성

- 버킷 생성 후 이름만 지어주고 기본 설정으로 생성

---

## **AMI 생성**

Amazon Machine Image, autoscaling group으로 생성될 ec2의 이미지

아래와 같이 인스턴스 생성

- 인스턴스 생성   
       
![image](https://github.com/junchanpp/cicd-test/assets/49396352/0153f4cd-ca16-4829-8cd1-9877cf3191d4)

    
![image](https://github.com/junchanpp/cicd-test/assets/49396352/662d0086-67c7-403f-a2d7-1f6eae2edd32)

    
- 키페어 생성 후 사용
    
![image](https://github.com/junchanpp/cicd-test/assets/49396352/044872ee-5805-4695-8bd4-7e01053eb014)

    
- 네트워크 설정은 새로 만든 VPC에 연결하여, 빠르게 템플릿을 만들기 위해 public영역의 subnet 선택.
       
![image](https://github.com/junchanpp/cicd-test/assets/49396352/b45f7132-d106-4a3f-8f9d-b2edca3cd459)

    
- 보안 그룹은 필요한 서비스를 설치하기 위해 빠르게 ssh만 허용하고 인스턴스 생성
- 템플릿의 ec2 설정
    
    우선 ec2에 접속(안되면 keypair의 권한을 실행가능하게 설정해주세요)
    
    ```bash
    sudo ssh -i ${keypair} ec2-user@${public_server_ip}
    ```
    
    1. 도커 설치
        
        ```bash
        //먼저 yum update부터
        sudo yum update
        // 도커 설치
        sudo yum install docker -y
        
        // 도커 실행
        sudo service docker start
        
        // 도커 상태 확인(확인 후 control+c)
        systemctl status docker.service
        
        //ec2-user에게 권한 부여
        sudo usermod -aG docker ec2-user
        
        //권한 부여 확인
        cat /etc/group
        ```
        
        - ec2-user에게 도커 권한 부여 필요
    
    1. EC2 CodeDeploy-Agent 설치
        
        codeDeploy-agent는 Ruby로 작성되었기 때문에 이를 EC2 에서 실행하기 위해 Ruby 패키지를 설치해주어야 함.
        
        ```bash
        sudo yum install ruby -y
        
        sudo yum install wget -y
        ```
        
        https://docs.aws.amazon.com/ko_kr/codedeploy/latest/userguide/codedeploy-agent-operations-install-linux.html
        
        ```bash
        wget https://aws-codedeploy-ap-northeast-2.s3.ap-northeast-2.amazonaws.com/latest/install
        chmod +x ./install
        ```
        
        다운로드한 install 파일을 실행하여 codedeploy-agent 를 설치
        
        > 📌 CodeDeploy Agent 설치 이슈
        > 
        > 
        > 공식문서에 따르면, 현재 Ubuntu 20.04 이상 버전에서 codedeploy-agent 설치 시 이슈가 있어 설치 과정의 출력을 임시 로그 파일에 작성하여 해결한다고 합니다.
        > 
        
        ```bash
        sudo ./install auto > /tmp/logfile
        ```
        
        CodeDeploy 데몬 실행 확인
        
        - codedeploy-agent 가 정상적으로 실행되고 있는지 확인합니다.
        
        ```bash
        sudo service codedeploy-agent status
        ```
        
        - 아래와 같은 문구가 출력되면 정상적으로 실행되고 있다는 의미입니다.
        
        ```bash
        "The AWS CodeDeploy agent is running"
        ```
        
        ### e) CodeDeploy 인스턴스 부팅 시 자동 실행 설정
        
        - 인스턴스가 부팅될 때마다 codedeploy-agent 가 자동 실행되도록 쉘스크립트 파일을 작성합니다.
        
        ```bash
        $ sudo vim /etc/init.d/codedeploy-startup.sh
        ```
        
        - 내용은 아래와 같습니다.
        
        ```bash
        #!/binsudo service codedeploy-agent restart
        ```
        
        - 해당 파일에 실행 권한을 부여하고 완료합니다.
        
        ```bash
        sudo chmod +x /etc/init.d/codedeploy-startup.sh
        ```
        
    2. ami 생성
        
        ec2에서 설정해야 할 기본 설정은 끝.
        
        ![image](https://github.com/junchanpp/cicd-test/assets/49396352/b2354c03-d073-4ac3-b8c3-ba17d8bb07e0)

        
        - 위 옵션을 통해 이미지 생성
        
        ![image](https://github.com/junchanpp/cicd-test/assets/49396352/e95c1c98-f332-456d-8d1e-6b635e7f9e7d)

        
        - 이름 적은 후 별다른 설정 없이 이미지 생성

---

## **시작 템플릿 생성**

사실 위에서 인스턴스에서 템플릿 생성해도 상관 없으나, 이미지를 만든 후 이미지를 통해 시작 템플릿 생성해보았음.

![image](https://github.com/junchanpp/cicd-test/assets/49396352/997cd3d6-322e-49a2-826b-cff2936d1957)



- 해당 메뉴로 접근(화면에 보이고 있는 이미 생성된 템플릿은 무시해주세요)

![image](https://github.com/junchanpp/cicd-test/assets/49396352/6b511f34-c624-4a0a-b595-07f9917a9f4e)


- 이름은 간단히 지은 후, ‘애플리케이션 및 OS 이미지’에서 내 AMI > 내 소유 > 방금 만든 이미지 를 선택

![image](https://github.com/junchanpp/cicd-test/assets/49396352/59dbfdc6-0432-459b-b870-d0657228f660)


- 인스턴스 유형 및 키페어 미리 선택

![image](https://github.com/junchanpp/cicd-test/assets/49396352/f09cac48-417f-4996-a3c9-0da1635b543d)


- subnet은 auto scaling에서 지정할거기 때문에 여기서는 선택하지 않는다.

![image](https://github.com/junchanpp/cicd-test/assets/49396352/d8068ad8-f06d-481c-8361-686b0c131bfb)


- 보안 규칙은 ssh 포트와 spring 포트를 허용

![image](https://github.com/junchanpp/cicd-test/assets/49396352/727212dd-89bb-471b-a909-3f543435a8a5)


- 그 후, 맨 아래에 고급 세부 정보에서 IAM 인스턴스 프로파일에서 위에서 만든 IAM Role인 AutoScalingRole 선택

---

## 타켓 그룹 생성

ec2 > 로드밸런싱 > 대상 그룹 선택

- 대상 유형 선택 > 인스턴스 선택

![image](https://github.com/junchanpp/cicd-test/assets/49396352/dcd09af1-8c4b-42b2-97e9-42a32fc4806a)


- 위와 같이 적어준다. 포트번호같은 경우, spring을 사용할거기 때문에 8080 이용

![image](https://github.com/junchanpp/cicd-test/assets/49396352/1ce77897-8eb5-4c07-b20f-dc8b645139b4)


- 상태검사 경로는 spring-actuator 사용할 예정이라 위와 같이 입력(걱정마세요… spring boot 프로젝트에 패키지 설치만 하면 자동으로 설정되는 api. 자세한 내용은 검색)

![image](https://github.com/junchanpp/cicd-test/assets/49396352/cdcc3422-e7b6-49aa-82d1-513570399e60)


- 고급 상태 검사 설정에서는 빠른 확인을 위해 값을 조금 조정. 그 후 다음 > 대상 그룹 생성

---

## 로드밸런서 생성

로드밸런서 생성 > Application Load Balancer 생성 선택

![image](https://github.com/junchanpp/cicd-test/assets/49396352/5ef33926-1d73-4c49-b8d2-4306271e04e8)


- 체계는 인터넷 경계를 선택해야 외부와 private subnet이 통신 가능

![image](https://github.com/junchanpp/cicd-test/assets/49396352/856d887b-b2db-4647-ad37-ceb2652f4491)


- 네트워크 매핑은 public subnet 선택

![image](https://github.com/junchanpp/cicd-test/assets/49396352/deeb8037-8cd6-4454-be66-e80cc7d9d3a5)


- 보안 그룹은 http만을 허용함 바로 아래의 리스너를 통해 80 → 8080으로 매핑
![image](https://github.com/junchanpp/cicd-test/assets/49396352/f0be5ffb-5418-4155-99a1-376de7a1d4ad)



- 리스너는 주소를 입력할 때 8080을 입력하는 귀찮음을 줄이기 위해 80으로 적음(load balancer에 의해 자동으로 80포트에 대한 접근이 targetGroup으로 인해 private subnet에서는 8080으로 요청이 들어옴)
- 그후 로드밸런서 생성

---

## **Auto Scaling Group 생성**

ec2 > auto scaling group > auto scaling group 생성 선택   
![image](https://github.com/junchanpp/cicd-test/assets/49396352/ceb88bbe-5bc1-4f5c-9931-6b36ffd18670)



- 만들어두었던 시작 템플릿 선택
   
![image](https://github.com/junchanpp/cicd-test/assets/49396352/34ca07af-3e35-4e5d-9bf1-084d4fab58f2)


- 네트워크에서 서브넷을 private subnet으로 선택해준다 → private subnet에 spring server 배포
![image](https://github.com/junchanpp/cicd-test/assets/49396352/47d44fb7-47b7-42d4-a9ba-b7c18fd000ba)


- 기존 로드밸런서 연결 > 만들어두었던 대상 그룹 선택
![image](https://github.com/junchanpp/cicd-test/assets/49396352/4598099c-7d3d-47f6-970a-c5c4489cfc17)


- auto scaling이 잘되는지 확인하기 위해 원하는 용량은 2로 설정. 그후 별다른 설정없이 생성 완료

---

## CodeDeploy 설정

codeDeploy를 검색 후 애플리케이션 생성 선택
![image](https://github.com/junchanpp/cicd-test/assets/49396352/c9682478-bd11-4f03-a212-5a3d6d82bc90)


- 이름을 정해주고, 컴퓨팅 플랫폼은 EC2/온프레미스 선택
- 그 후 배포 그룹 생성 선택
![image](https://github.com/junchanpp/cicd-test/assets/49396352/7b2ffd2e-08bc-4c83-b369-693b87e68c5c)


- 배포 그룹 이름을 짓고, 서비스 역할은 위에서 만든 CodeDeployAutoScalingRole을 선택한다.
- 배포 유형은 블루/그린 전략을 선택한다(현재 위치 전략은 rolling 배포 전략으로, 검색하면 차이점이 나옵니다.)
- 환경구성은 Amazon EC2 Auto Scaling 그룹 자동 복사 선택← 블루,그린 전환할 때 마다 AutoScaling Group도 블루, 그린으로 나뉘어서 생성됨.
![image](https://github.com/junchanpp/cicd-test/assets/49396352/31454f22-37ea-47ab-9c54-35784105b600)


- 로드밸런서의 대상그룹은 만들어둔 대상 그룹 선택

---

## 코드 작성

- 우선 repository를 하나 생성하자
- 프로젝트 최상단에 appspec.yml 생성
    
    ```yaml
    version: 0.0
    os: linux
    files:
      - source: /
        destination: /home/ec2-user/app
        overwrite: yes
    
    permissions:
      - object: /
        pattern: "**"
        owner: ec2-user
        group: ec2-user
        mode: 755
    
    hooks:
      AfterInstall:
        - location: scripts/deploy.sh
          timeout: 60
          runas: ec2-user
    ```
    
    - files에서 선언한 코드로 인해 S3에 업로드된 zip 파일의 압축을 풀어 /home/ec2-user/app으로 동
    - 이동시키기 전에 파일들의 권한 설정
    - hooks는 codeDeploy를 통해 ec2에 다운받은 파일을 실행한다.
- 프로젝트 최상단에 Dockerfile 작성
    
    ```bash
    FROM openjdk:17-oracle AS builder
    RUN microdnf install findutils
    COPY gradlew .
    COPY settings.gradle .
    COPY build.gradle .
    COPY gradle gradle
    COPY src src
    COPY backend-config backend-config
    RUN chmod +x ./gradlew
    RUN ls -la
    RUN ./gradlew build
    
    FROM openjdk:17-oracle
    RUN mkdir /opt/app
    COPY --from=builder build/libs/*.jar /opt/app/spring-boot-application.jar
    EXPOSE 8080
    ENV	PROFILE local
    ENTRYPOINT ["java", "-jar", "-Dspring.profiles.active=${PROFILE}" ,"/opt/app/spring-boot-application.jar"]
    ```
    

- .github/workflows/aws.yml(파일이름은 상관없음) 생성 후 아래 내용 작성
    
    ```yaml
    name: Deploy to dev env
    
    on:
        push:
            branches: [ dev ]
    jobs:
        build-docker:
            runs-on: ubuntu-latest
            steps:
                - name: checkout
                  uses: actions/checkout@v2
    
                - name: setup jdk 17
                  uses: actions/setup-java@v3
                  with:
                      distribution: 'adopt'
                      java-version: '17'
    
                - name: add permission to gradlew
                  run: chmod +x ./gradlew
                  shell: bash
    
                - name: aws configure
                  uses: aws-actions/configure-aws-credentials@v2
                  with:
                      aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
                      aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
                      aws-region: us-east-1 #본인의 리전 입력. 퍼블릭이면 아마 서울이 안돼서 버지니아 북부로 설정
    
                - name: Login to ECR
                  id: login-ecr
                  uses: aws-actions/amazon-ecr-login@v1
                  with:
                    registry-type: public
    
                - name: build docker file and setting deploy files
                  env:
                    ECR_REGISTRY: ${{ steps.login-ecr.outputs.registry }}
                    ECR_REPOSITORY: #본인 레파지토리의 이름
                    ECR_REGISTRY_ALIAS: #본인의 레지스트리의 별칭
                    IMAGE_TAG: ${{ github.sha }}
                  run: |
                    docker build -t $ECR_REGISTRY/$ECR_REGISTRY_ALIAS/$ECR_REPOSITORY:$IMAGE_TAG .
                    docker push $ECR_REGISTRY/$ECR_REGISTRY_ALIAS/$ECR_REPOSITORY:$IMAGE_TAG
                    echo "image=$ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG" >> $GITHUB_OUTPUT
                    mkdir scripts
                    touch scripts/deploy.sh
                    echo "aws ecr get-login-password --region ap-northeast-2 | docker login --username AWS --password-stdin public.ecr.aws/$ECR_REGISTRY_ALIAS" >> scripts/deploy.sh
                    echo "docker pull public.ecr.aws/$ECR_REGISTRY_ALIAS/$ECR_REPOSITORY:$IMAGE_TAG" >> scripts/deploy.sh
                    echo "docker run -p 8080:8080 -e PROFILE=dev -d --restart always --name test public.ecr.aws/$ECR_REGISTRY_ALIAS/$ECR_REPOSITORY:$IMAGE_TAG" >> scripts/deploy.sh
                - name: upload to s3
                  env:
                    IMAGE_TAG: ${{ github.sha }}
                  run: |
                    zip -r deploy-$IMAGE_TAG.zip ./scripts appspec.yml
                    aws s3 cp --region {s3의 region} --acl private ./deploy-$IMAGE_TAG.zip s3://{s3의 버킷}
                - name: start deploy
                  env:
                    IMAGE_TAG: ${{ github.sha }}
                  run: |
                    aws deploy create-deployment --region {codeDeploy의 region} \
                    --application-name {codeDeploy 이름}  \
                    --deployment-config-name CodeDeployDefault.OneAtATime \
                    --deployment-group-name {codeDeployGroup 이름}  \
                    --s3-location bucket={s3의 버킷},bundleType=zip,key=deploy-$IMAGE_TAG.zip
    ```
    

---

## 드디어 끝

이제 dev 브랜치로 push하면 자동 배포가 됩니다.
![image](https://github.com/junchanpp/cicd-test/assets/49396352/64168073-2f5f-4065-81a6-5e1ea108461a)


- Github actions 탭을 확인해보면 일정시간 이후 완료된 것을 알 수 있음. 하지만 code deploy의 프로세스에서는 현재 이곳에서 확인 불가. aws에서 확인 가능
![image](https://github.com/junchanpp/cicd-test/assets/49396352/1e9b5696-00f3-4ff5-a233-7fcb45f5afc7)


- 배포 중임을 확인할 수 있음

---

# 아쉬운 점

- 네트워크 매핑 과정에서 가용영역을 ap-northeast-2a,2b로 잘못 선택했다. t2-micro는 ap-northeast-2a,2c만 지원하고, 2b와 2d를 지원하지 못한다는 것을 몰랐다. 그로 인해서인지, 2b에는 배포가 되지 않았다. → 하지만 이것도 정확한 원인파악을 하지 못해 파악 필요 → 글을 작성하며 해결했습니다.
- 네트워크 구성을 잘 하지 못했다. public과 private subnet을 제대로 나누지 못했고, 우선 public subnet에서만 진행했다. 네트워크 구성을 실제 서비스 운영 서버로 생각하고 다시 구성하여 CICD를 구현해보고 싶다. → 글을 작성하면서 구별지었습니다.
- CICD를 한 번 진행하는데에 너무 오랜 시간이 걸린다. CI(github actions)가 2분정도 걸리고, CD가 8분정도 걸린다. 시간을 더 단축해보고 싶다. 또한 github actions를 통해서 CD의 진행과정이 표시되지 않는다. CICD의 진행과정을 한 눈에 보도록 구성하고 싶다. → https://www.jongho.dev/aws/aws-codedeploy-speed-up/ 줄일 수 있는 방법을 확인했습니다. 글에는 적지 않았지만, 수정해볼 예정입니다. -> toy-project에서 다른 방식을 사용하여(정석은 아닌 것 같지만) 해결하였습니다.

---

그래도 진행하면서 autoscaling이나, code deploy, github actions, load balancer의 이해도는 확실히 높아진 것 같다 !



# 참고자료

https://keencho.github.io/posts/aws-cicd-1/
https://velog.io/@kshired/Github-Actions-ECR-Auto-Scaling-Group-EC2-CodeDeploy-S3-%EB%A5%BC-%EC%82%AC%EC%9A%A9%ED%95%98%EC%97%AC-BlueGreen-CICD-%EA%B5%AC%EC%B6%95%ED%95%98%EA%B8%B0#auto-scaling-role
https://velog.io/@ch4570/Github-Actions-Nginx%EB%A5%BC-%EC%9D%B4%EC%9A%A9%ED%95%9C-CICD-%EB%AC%B4%EC%A4%91%EB%8B%A8-%EB%B0%B0%ED%8F%AC-%EC%9E%90%EB%8F%99%ED%99%94-%EA%B5%AC%EC%B6%95-EC2-S3-%EC%84%A4%EC%A0%95#-ec2-%EC%9D%B8%EC%8A%A4%ED%84%B4%EC%8A%A4-%EB%A7%8C%EB%93%A4%EA%B8%B0
