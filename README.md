# OpenMinted Service http://inb.bsc.es/service/openminted/
- [Motivation](#motivation)
- [Description](#description)
- [Requirements](#requirements)
- [Deployment](#deployment)
  - [Service](#service)
  - [Test](#test)
- [Development](#development)
- [Contributing](#contributing)
- [Contributors](#contributors)
- [Acknowledgments](#acknowledgments)
- [Funding](#funding)

## Motivation
Provide a command line annotator wrapper container (in this case, [NLProt](https://rostlab.org/owiki/index.php/NLProt)) with an [REST API](https://en.wikipedia.org/wiki/Representational_state_transfer) container to the [OpenMinted Platform Registry](https://services.openminted.eu/) according the [OpenMinted API Specification](https://openminted.github.io/releases/processing-web-services/1.0.0/specification)

## Description
  [OpenMinTeD](http://openminted.eu/) aspires to enable the creation of an infrastructure that fosters and facilitates the use of text mining technologies in the scientific publications world, builds on existing text mining tools and platforms, and renders them discoverable and interoperablethrough appropriate registries and a standards-based interoperability layer, respectively.

  http://openminted.eu/

## Requirements
* [_docker_](https://docs.docker.com/install/)

* [_docker-compose_](https://docs.docker.com/compose/install/#install-compose)

* [_Nginx_](https://nginx.org/en/)
   ```
   # cp etc/nginx/sites-available/openminted-service /etc/nginx/sites-available

   # ln -s /etc/nginx/sites-available/openminted-service /etc/nginx/sites-enabled/

   # systemctl restart nginx
   ```
## Deployment
### Service
```
docker-compose build
docker-compose up -d
```
### Test
`curl -F cas=@TP53.pdf localhost:8080/process`


## Development
[Crystal](https://crystal-lang.org/)

[Kemal](http://kemalcr.com/)

## Contributing

1. Fork it ( https://github.com/inab/openminted-service/fork )
2. Create your feature branch (git checkout -b my-new-feature)
3. Commit your changes (git commit -am 'Add some feature')
4. Push to the branch (git push origin my-new-feature)
5. Create a new Pull Request

## Contributors

- Miguel Madrid Mencía ([mimadrid](https://github.com/mimadrid)) - creator, maintainer

## Acknowledgments
Sven Mika, Burkhard Rost; NLProt: extracting protein names and sequences from papers, Nucleic Acids Research, Volume 32, Issue suppl_2, 1 July 2004, Pages W634–W637, https://doi.org/10.1093/nar/gkh427

## Funding
OpenMinted (654021) is a H2020 project funded by the European Commission.