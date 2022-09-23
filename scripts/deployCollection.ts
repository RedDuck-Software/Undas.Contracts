
async function main3() {
    const collectionFactory = await ethers.getContractFactory("UndasMVP");
    // const collectionContract = await (await collectionFactory.deploy()).deployed();

    let assets = [
        'https://lh3.googleusercontent.com/uYuQsUX2GWXZfsb_5xME48p2HzboojZbr9keLylvzj4LY6YBj40aUvmEW8lo39vXyVcc60PCQoaG5ItL-CM7zJHjQVh7soquUb2ZkA=w600',
        'https://lh3.googleusercontent.com/dsDsTpXBK7O7LGzFQJeM-4FBy3fYMBvfLGFObZPih76Vlq6o_4gfB7fIrwLaYS-CdnE7WtwKEOApBN7m6iSiq4W17-iSIXHQDUQd=w600',
        'https://lh3.googleusercontent.com/Gecvm67BSyrkXt0n1GwlQrk0qHpXlPAVoUZhH6iA3AVsjROe5npjFt9VvmyXPQDz6Yn3a8_H5jCV-F9r7gHyK31y-NdHv9HnPu9ooW4=w600']

            
    // console.log('nftCollection deployed to: ',collectionContract.address);
}
main3().catch((error) => {
console.error(error);
process.exitCode = 1;
});
